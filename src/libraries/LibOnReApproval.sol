// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {LibOnReStorage} from "../diamond/LibOnReStorage.sol";
import {ApprovalMessage} from "../types/OnReTypes.sol";

/// @notice EIP-712 approval verification for permissioned offer execution.
library LibOnReApproval {
    // Approval confirms temporary KYC eligibility, not a specific action.
    // Replay until expiry is intentional: approved users may perform any permissioned action.
    bytes32 private constant APPROVAL_TYPEHASH = keccak256("ApprovalMessage(address user,uint64 expiry)");
    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant EIP712_NAME_HASH = keccak256("OnReApp");
    bytes32 private constant EIP712_VERSION_HASH = keccak256("1");

    function isValidForUser(address user, ApprovalMessage calldata approval, bytes calldata signature)
        internal
        view
        returns (bool)
    {
        // forge-lint: disable-next-line(block-timestamp)
        if (user == address(0) || approval.user != user || block.timestamp > approval.expiry) return false;
        (address signer, ECDSA.RecoverError recoverError,) =
            ECDSA.tryRecoverCalldata(_approvalDigest(approval), signature);
        return recoverError == ECDSA.RecoverError.NoError
            && (signer == LibOnReStorage.appStorage().approver1 || signer == LibOnReStorage.appStorage().approver2);
    }

    function _approvalDigest(ApprovalMessage calldata approval) private view returns (bytes32) {
        bytes32 domainSeparator = keccak256(
            abi.encode(EIP712_DOMAIN_TYPEHASH, EIP712_NAME_HASH, EIP712_VERSION_HASH, block.chainid, address(this))
        );
        bytes32 structHash = keccak256(abi.encode(APPROVAL_TYPEHASH, approval.user, approval.expiry));
        return keccak256(abi.encodePacked(hex"1901", domainSeparator, structHash));
    }
}
