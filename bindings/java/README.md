# OnRe EVM Java bindings

[web3j](https://github.com/LFDT-web3j/web3j) wrapper for the OnRe diamond, generated from the
merged ABI that `gemforge build` writes to `src/generated/abi.json`, and published as a Maven
package.

The wrapper is `com.onre.evm.IDiamondProxy`. It carries every function callable on the proxy
and every event and custom error in the merged ABI, including the `ManagedToken` events
(`Transfer`, mint/burn access changes) and a handful of forge-std and OpenZeppelin proxy events that
Gemforge merges in. The ABI ships inside the jar as `abi/IDiamondProxy.json`.

## Consuming the package

Packages are published to this repository's GitHub Packages Maven registry. GitHub requires a token
with `read:packages` even for public repositories.

```kotlin
// settings.gradle.kts or build.gradle.kts
repositories {
    mavenCentral()
    maven {
        url = uri("https://maven.pkg.github.com/onre-finance/onre-evm")
        credentials {
            username = providers.gradleProperty("gpr.user").orElse(providers.environmentVariable("GITHUB_ACTOR")).get()
            password = providers.gradleProperty("gpr.key").orElse(providers.environmentVariable("GITHUB_TOKEN")).get()
        }
    }
}

dependencies {
    implementation("com.onre.evm:onre-evm-java:<version>")
}
```

The jar declares `org.web3j:core` as a transitive `api` dependency at the version in
`gradle.properties` (`web3jVersion`). web3j 5.x and 6.x are built for Java 21. A consumer that
pins a different web3j version should rebuild the bindings with that version
(`-Pweb3jVersion=...`) rather than mixing versions, because the generated code is compiled against
web3j's ABI type classes.

### Decoding events

```java
// From a receipt of a transaction sent to the proxy:
IDiamondProxy proxy = IDiamondProxy.load(diamondAddress, web3j, transactionManager, gasProvider);
for (IDiamondProxy.OfferExecutedEventResponse e : IDiamondProxy.getOfferExecutedEvents(receipt)) {
    // e.offerConfigId, e.user, e.amountOut, ...
}

// Or from a raw log:
EthFilter filter = new EthFilter(from, to, diamondAddress)
        .addSingleTopic(EventEncoder.encode(IDiamondProxy.OFFEREXECUTED_EVENT));
proxy.offerExecutedEventFlowable(filter).subscribe(e -> ...);
```

Every event `X` is exposed as `IDiamondProxy.X_EVENT`, `IDiamondProxy.XEventResponse`,
`IDiamondProxy.getXEvents(TransactionReceipt)` and `proxy.xEventFlowable(...)`. Events are decoded
by signature, so the `Transfer` and access events of a managed token can be decoded with the same
class by filtering on the token's address instead of the proxy's.

## Building locally

Requires JDK 21+, Node 20+ with pnpm, and Foundry, as for the rest of the repository.

```sh
cd bindings/java
./gradlew build                     # runs `pnpm build` at the repo root, then generates, compiles and tests
./gradlew build -PforgeBuild=false  # reuse the src/generated/abi.json already present
./gradlew publishToMavenLocal -Pversion=1.0.0-SNAPSHOT
```

Outputs:

- `build/libs/onre-evm-java-<version>.jar` and `-sources.jar`
- `build/abi/IDiamondProxy.json`, the ABI the wrapper was generated from
- `build/generated/sources/web3j/java`, the generated source

`./gradlew test` checks that every event in the ABI has a matching static `Event` on the wrapper, so
a dropped event fails the build rather than surfacing in a consumer.

## Publishing

The `Java bindings` workflow (`.github/workflows/java-bindings.yml`) is run manually from the
Actions tab. It takes the Maven version to publish, builds from the selected ref, uploads the jar as
a workflow artifact, and publishes `com.onre.evm:onre-evm-java:<version>` with the workflow's
`GITHUB_TOKEN`. Untick `publish` to only build.

Versions are not derived from git. Pick a version that tells consumers which contract deployment it
matches, and use a `-SNAPSHOT` suffix for anything not yet deployed.

To publish from a workstation instead, set `gpr.user` and `gpr.key` (a token with `write:packages`)
in `~/.gradle/gradle.properties` and run `./gradlew publish -Pversion=<version>`.

## Configuration

`gradle.properties`:

| Property       | Default            | Meaning                                                              |
| -------------- | ------------------ | -------------------------------------------------------------------- |
| `version`      | `1.0.0-SNAPSHOT`   | Maven version; override with `-Pversion`                             |
| `web3jVersion` | `6.0.0`            | web3j release used for codegen and declared as the `api` dependency  |
| `javaRelease`  | `21`               | `--release` passed to `javac`                                        |
| `javaPackage`  | `com.onre.evm`     | Package of the generated wrapper                                     |
| `forgeBuild`   | `true`             | Run `pnpm build` before staging the ABI                              |
