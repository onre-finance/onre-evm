// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReStorage} from "../diamond/libraries/LibOnReStorage.sol";
import {IOnReAppErrors} from "../interfaces/IOnReAppErrors.sol";
import {IOnReAppEvents} from "../interfaces/IOnReAppEvents.sol";
import {OnReTypes} from "../types/OnReTypes.sol";
import {LibOnReAccessControl} from "./LibOnReAccessControl.sol";
import {LibOnReRoles} from "./LibOnReRoles.sol";
import {LibOnReValidation} from "./LibOnReValidation.sol";
import {OnReIds} from "./OnReIds.sol";
import {OnReMath} from "./OnReMath.sol";

/// @notice Reusable USD price production for OnRe tokens.
library LibOnRePricer {
    uint8 internal constant MAX_VECTORS = 10;
    uint256 internal constant PRICE_SCALE = 1e9;

    function createPricer(address onReToken, OnReTypes.PricingDenomination denomination)
        internal
        returns (bytes32 pricerId)
    {
        LibOnReAccessControl.checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        LibOnReValidation.requireEnabledOnReToken(onReToken);

        pricerId = OnReIds.pricerId(onReToken, denomination);
        OnReTypes.Pricer storage pricer = LibOnReStorage.appStorage().pricers[pricerId];
        if (pricer.exists) revert IOnReAppErrors.PricerAlreadyExistsError(pricerId);

        pricer.onReToken = onReToken;
        pricer.denomination = denomination;
        pricer.exists = true;
        emit IOnReAppEvents.PricerCreated(pricerId, onReToken, denomination);
    }

    function addPricingVector(bytes32 pricerId, OnReTypes.PricingVector calldata vector) internal {
        LibOnReAccessControl.checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        OnReTypes.Pricer storage pricer = LibOnReValidation.requirePricer(pricerId);
        if (vector.startTime == 0 || vector.baseTime == 0 || vector.basePrice == 0 || vector.priceFixDuration == 0) {
            revert IOnReAppErrors.InvalidAmountError();
        }
        if (vector.baseTime > vector.startTime) {
            revert IOnReAppErrors.VectorBaseTimeAfterStartTimeError(vector.baseTime, vector.startTime);
        }

        uint64 currentTime = uint64(block.timestamp);
        if (vector.startTime < currentTime) {
            revert IOnReAppErrors.VectorStartTimeInPastError(vector.startTime, currentTime);
        }

        uint8 vectorCount = pricer.vectorCount;
        if (vectorCount > 0) {
            uint64 latestStartTime = pricer.vectors[vectorCount - 1].startTime;
            if (vector.startTime == latestStartTime) {
                revert IOnReAppErrors.DuplicateVectorStartTimeError(vector.startTime);
            }
            if (vector.startTime < latestStartTime) revert IOnReAppErrors.InvalidVectorOrderError();
        }

        _cleanOldPricingVectors(pricerId, pricer, vector.startTime, currentTime);
        vectorCount = pricer.vectorCount;
        if (vectorCount >= MAX_VECTORS) revert IOnReAppErrors.TooManyVectorsError();

        pricer.vectors[vectorCount] = vector;
        pricer.vectorCount = vectorCount + 1;
        emit IOnReAppEvents.PricingVectorAdded(
            pricerId, vector.startTime, vector.baseTime, vector.basePrice, vector.apr, vector.priceFixDuration
        );
    }

    function deletePricingVector(bytes32 pricerId, uint64 startTime) internal {
        LibOnReAccessControl.checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        // forge-lint: disable-next-line(block-timestamp)
        if (startTime <= block.timestamp) {
            revert IOnReAppErrors.VectorStartTimeInPastError(startTime, uint64(block.timestamp));
        }

        OnReTypes.Pricer storage pricer = LibOnReValidation.requirePricer(pricerId);
        uint8 vectorCount = pricer.vectorCount;
        uint8 vectorIndex = type(uint8).max;
        for (uint8 i; i < vectorCount;) {
            if (pricer.vectors[i].startTime == startTime) {
                vectorIndex = i;
                break;
            }
            unchecked {
                ++i;
            }
        }
        if (vectorIndex == type(uint8).max) revert IOnReAppErrors.VectorNotFoundError(startTime);

        _removePricingVectorAt(pricer, vectorIndex);
        emit IOnReAppEvents.PricingVectorDeleted(pricerId, startTime);
    }

    function deleteAllPricingVectors(bytes32 pricerId) internal {
        LibOnReAccessControl.checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        OnReTypes.Pricer storage pricer = LibOnReValidation.requirePricer(pricerId);
        uint8 deletedCount = pricer.vectorCount;
        for (uint8 i; i < deletedCount;) {
            delete pricer.vectors[i];
            unchecked {
                ++i;
            }
        }
        pricer.vectorCount = 0;
        emit IOnReAppEvents.AllPricingVectorsDeleted(pricerId, deletedCount);
    }

    function setPricerDisabled(bytes32 pricerId, bool disabled) internal {
        LibOnReAccessControl.checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        OnReTypes.Pricer storage pricer = LibOnReValidation.requirePricer(pricerId);
        if (pricer.disabled == disabled) revert IOnReAppErrors.NoChangeError();
        pricer.disabled = disabled;
        emit IOnReAppEvents.PricerDisabledSet(pricerId, disabled);
    }

    function currentPrice(bytes32 pricerId) internal view returns (uint256) {
        OnReTypes.Pricer storage pricer = LibOnReValidation.requireExecutablePricer(pricerId);
        return calculatePricingVectorPriceAt(activePricingVector(pricerId, pricer), block.timestamp);
    }

    function activePricingVector(bytes32 pricerId, OnReTypes.Pricer storage pricer)
        internal
        view
        returns (OnReTypes.PricingVector storage)
    {
        return pricer.vectors[activePricingVectorIndex(pricerId, pricer)];
    }

    function activePricingVectorIndex(bytes32 pricerId, OnReTypes.Pricer storage pricer) internal view returns (uint8) {
        for (uint8 i = pricer.vectorCount; i > 0;) {
            unchecked {
                --i;
            }
            // forge-lint: disable-next-line(block-timestamp)
            if (pricer.vectors[i].startTime <= block.timestamp) return i;
        }
        revert IOnReAppErrors.NoActiveVectorError(pricerId);
    }

    function calculatePricingVectorPriceAt(OnReTypes.PricingVector storage vector, uint256 timestamp)
        internal
        view
        returns (uint256)
    {
        return OnReMath.calculateStepPrice(
            vector.apr, vector.basePrice, vector.baseTime, vector.priceFixDuration, timestamp
        );
    }

    function _cleanOldPricingVectors(
        bytes32 pricerId,
        OnReTypes.Pricer storage pricer,
        uint64 newStartTime,
        uint64 currentTime
    ) private {
        uint8 vectorCount = pricer.vectorCount;
        if (vectorCount < 2) return;

        uint64 activeStartTime = newStartTime == currentTime ? newStartTime : 0;
        if (activeStartTime == 0) {
            for (uint8 i = vectorCount; i > 0;) {
                unchecked {
                    --i;
                }
                uint64 candidateStartTime = pricer.vectors[i].startTime;
                if (candidateStartTime <= currentTime) {
                    activeStartTime = candidateStartTime;
                    break;
                }
            }
        }
        if (activeStartTime == 0) return;

        uint64 previousStartTime = 0;
        for (uint8 i; i < vectorCount;) {
            uint64 candidateStartTime = pricer.vectors[i].startTime;
            if (candidateStartTime < activeStartTime && candidateStartTime > previousStartTime) {
                previousStartTime = candidateStartTime;
            }
            unchecked {
                ++i;
            }
        }
        if (previousStartTime == 0) return;

        uint8 writeIndex = 0;
        for (uint8 readIndex; readIndex < vectorCount;) {
            uint64 startTime = pricer.vectors[readIndex].startTime;
            bool evict = startTime < activeStartTime && startTime != previousStartTime;
            if (evict) {
                emit IOnReAppEvents.PricingVectorEvicted(pricerId, startTime);
            } else {
                if (writeIndex != readIndex) pricer.vectors[writeIndex] = pricer.vectors[readIndex];
                unchecked {
                    ++writeIndex;
                }
            }
            unchecked {
                ++readIndex;
            }
        }

        for (uint8 i = writeIndex; i < vectorCount;) {
            delete pricer.vectors[i];
            unchecked {
                ++i;
            }
        }
        pricer.vectorCount = writeIndex;
    }

    function _removePricingVectorAt(OnReTypes.Pricer storage pricer, uint8 vectorIndex) private {
        uint8 lastIndex = pricer.vectorCount - 1;
        for (uint8 i = vectorIndex; i < lastIndex;) {
            pricer.vectors[i] = pricer.vectors[i + 1];
            unchecked {
                ++i;
            }
        }
        delete pricer.vectors[lastIndex];
        pricer.vectorCount = lastIndex;
    }
}
