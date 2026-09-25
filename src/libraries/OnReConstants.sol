// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

// Shared financial units and precision.
uint16 constant MAX_BASIS_POINTS = 10_000;
uint256 constant APR_SCALE = 1_000_000;
uint256 constant PRICE_DECIMALS = 9;
uint256 constant PRICE_SCALE = 10 ** PRICE_DECIMALS;
uint8 constant MAX_TOKEN_DECIMALS = 18;

// Fixed 365-day year used by pricing and buffer accrual.
uint256 constant DAYS_PER_YEAR = 365;
uint256 constant SECONDS_IN_DAY = 1 days;
uint256 constant SECONDS_PER_YEAR = DAYS_PER_YEAR * SECONDS_IN_DAY;
