Vendored dependency sources retain their original license headers and licenses.

- Circle stablecoin-evm: https://github.com/circlefin/stablecoin-evm/tree/fc85788bc7c23cefe3df1a757133048bfddadeaa
  Only the transitive dependencies of FiatTokenV2_2.sol are included.
  Local change: SignatureChecker.isValidSignatureNow has internal visibility instead of external visibility, so its code is embedded without deploying a separate library.
- OpenZeppelin Contracts v3.4.2: https://github.com/OpenZeppelin/openzeppelin-contracts/tree/8e0296096449d9b1cd7c5631e917330635244c37
  Only the transitive dependencies required by the Circle sources are included, without modifications.
