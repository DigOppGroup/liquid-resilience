// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {Vault} from "./Vault.sol";

/// @author Digital Opportunities Group
/// @title VaultFactory
contract VaultFactory {
    address public immutable owner;
    uint16 public basisPointFee;
    uint16 public constant BPS = 10_000;
    address[] public vaults;

    error ExceedsMaxBPS(uint256 bps, uint256 maxBPS);
    error NotOwner(address caller, address owner);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner({caller: msg.sender, owner: owner});
        _;
    }

    modifier validBasisPoints(uint16 _feeBasisPoints) {
        if (_feeBasisPoints > BPS) revert ExceedsMaxBPS({bps: _feeBasisPoints, maxBPS: BPS});
        _;
    }

    /// @param maker address of the maker of the new vault
    /// @param vaultAddress address of the newly created vault
    event VaultCreated(address indexed maker, address indexed vaultAddress);

    constructor(uint16 _basisPointFee) validBasisPoints(_basisPointFee) {
        owner = msg.sender;
        basisPointFee = _basisPointFee;
    }

    /// @param _maker address of the maker of the new vault
    /// @param _makerRevenueBasisPoints percentage of the rewards that the maker will receive in basis points
    /// @param _makerToken address of token0 for the Velodrome pool, which will be provided by the taker
    /// @param _maturity block timestamp time in seconds when the vault matures
    /// @param _router address of the Velodrome Router
    /// @param _slippageBasisPoints the maximum slippage in basis points that the maker is willing to accept
    /// @param _stable indicates if the pool is stable or volatile
    /// @param _takerToken address of token1 for the Velodrome pool, which will be provided by the taker
    /// @return address of the created vault
    function createVault(
        address _maker,
        uint16 _makerRevenueBasisPoints,
        address _makerToken,
        uint256 _maturity,
        address _router,
        uint16 _slippageBasisPoints,
        bool _stable,
        address _takerToken
    )
        external
        onlyOwner
        validBasisPoints(_makerRevenueBasisPoints)
        validBasisPoints(_slippageBasisPoints)
        returns (address)
    {
        Vault vault = new Vault(
            basisPointFee,
            _maker,
            _makerRevenueBasisPoints,
            _makerToken,
            _maturity,
            _router,
            _slippageBasisPoints,
            _stable,
            _takerToken
        );
        emit VaultCreated(_maker, address(vault));
        vaults.push(address(vault));
        return address(vault);
    }

    /// @notice the maximum fee is 10,000 basis points (or 100% of rewards)
    /// @param _basisPointFee new fee in basis points that will be paid to the owner of the factory
    function setBasisPointFee(uint16 _basisPointFee) external onlyOwner validBasisPoints(_basisPointFee) {
        basisPointFee = _basisPointFee;
    }

    /// @return number of vaults
    function getVaultsSize() public view returns (uint256) {
        return vaults.length;
    }
}
