// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {Vault} from "../../src/Vault.sol";

abstract contract TestHelpers {
    address internal constant MAKER = address(100);
    address internal constant TAKER = address(101);
    address internal constant MAKER_TOKEN = VELO;
    address internal constant TAKER_TOKEN = USDC;
    uint256 internal constant DEFAULT_MATURITY = 30 days;
    bool internal constant STABLE = true;
    uint256 internal makerAmount = 1e20;
    uint256 internal takerAmount = 1e6;
    uint16 internal basisPointFee = 1000; // 10%
    uint16 internal makerRevBasisPoints = 4500; // 45%

    ////////////////////////////////////////////////////////////////////////////////////
    // VELO PROTOCOL
    ////////////////////////////////////////////////////////////////////////////////////
    address internal constant POOL = 0x8134A2fDC127549480865fB8E5A9E8A8a95a54c5;
    address internal constant ROUTER = 0xa062aE8A9c5e11aaA026fc2670B0D65cCc8B2858;
    address internal constant VOTER = 0x41C914ee0c7E1A5edCD0295623e6dC557B5aBf3C;
    address internal constant USDC = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
    address internal constant VELO = 0x9560e827aF36c94D2Ac33a39bCE1Fe78631088Db;
}
