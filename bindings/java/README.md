# OnRe EVM Java bindings

[web3j](https://github.com/LFDT-web3j/web3j) wrappers for the OnRe diamond and managed tokens,
generated from the contract ABIs and published together as a Maven package.

- `com.onre.evm.IDiamondProxy`: generated from the merged Diamond ABI at `src/generated/abi.json`.
- `com.onre.evm.ManagedToken`: generated from the full contract artifact at
  `out/ManagedToken.sol/ManagedToken.json`, including inherited ERC-20 metadata and token methods.

Both ABIs ship inside the jar as `abi/IDiamondProxy.json` and `abi/ManagedToken.json`.

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
    implementation("com.onre:onre-evm-java:<version>")
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

Each wrapper exposes its events as static event definitions, typed response classes, receipt
extractors, and event flowables. Use `IDiamondProxy` for Diamond logs and `ManagedToken` for token logs.

### Reading token metadata

Load the token wrapper at the token's proxy address:

```java
ManagedToken token = ManagedToken.load(tokenAddress, web3j, transactionManager, gasProvider);
String name = token.name().send();
String symbol = token.symbol().send();
BigInteger decimals = token.decimals().send();
```

The wrapper also exposes the contract's other methods, such as `balanceOf`, `totalSupply`,
`getCCIPAdmin`, `maxSupply`, and `maxMintAmount`.

## Building locally

Requires JDK 21+, Node 20+ with pnpm, and Foundry, as for the rest of the repository.

```sh
cd bindings/java
./gradlew build                     # runs `pnpm build` at the repo root, then generates, compiles and tests
./gradlew build -PforgeBuild=false  # reuse existing Diamond ABI and ManagedToken Forge artifact
./gradlew publishToMavenLocal      # installs the version from gradle.properties into ~/.m2
```

Outputs:

- `build/libs/onre-evm-java-<version>.jar` and `-sources.jar`
- `build/abi/IDiamondProxy.json` and `build/abi/ManagedToken.json`, the source ABIs
- `build/generated/sources/web3j/java`, the generated source

`./gradlew test` checks that every event in each ABI has a matching static `Event` on its wrapper
and that the token metadata calls expose typed return values.

## Publishing

The `Java bindings` workflow (`.github/workflows/java-bindings.yml`) is run manually from the
Actions tab. It publishes the version in `gradle.properties` (`version=`) from the selected ref,
uploads the jar as a workflow artifact, and pushes `com.onre:onre-evm-java:<version>` to GitHub
Packages with the workflow's `GITHUB_TOKEN`. Untick `publish` to only build.

To release, bump `version=` in `gradle.properties`, commit, and run the workflow on that commit.
Versions are not derived from git. Pick a version that tells consumers which contract deployment it
matches, and use a `-SNAPSHOT` suffix for anything not yet deployed.

GitHub Packages refuses a second upload of a release version, so re-running the workflow on an
already-published version fails before publishing. Tick `overwrite` to delete the published version
and publish again in its place; consumers that already resolved the old jar must refresh
(`./gradlew --refresh-dependencies`). `-SNAPSHOT` versions can be re-published without `overwrite`.

The delete uses the workflow token. If GitHub ever refuses it, add a repository secret
`PACKAGES_TOKEN` holding a classic personal access token with `read:packages` and
`delete:packages`, and the workflow will use it for the check and delete steps.

To publish from a workstation instead, set `gpr.user` and `gpr.key` (a token with `write:packages`)
in `~/.gradle/gradle.properties` and run `./gradlew publish`, or `./gradlew publish -Pversion=<version>`
to override the version.

## Configuration

`gradle.properties`:

| Property       | Default            | Meaning                                                              |
| -------------- | ------------------ | -------------------------------------------------------------------- |
| `version`      | `1.0.1`            | Maven version; override with `-Pversion`                             |
| `web3jVersion` | `6.0.0`            | web3j release used for codegen and declared as the `api` dependency  |
| `javaRelease`  | `21`               | `--release` passed to `javac`                                        |
| `javaPackage`  | `com.onre.evm`     | Package of the generated wrappers                                    |
| `forgeBuild`   | `true`             | Run `pnpm build` before staging the ABIs                             |
