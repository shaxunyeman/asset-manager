// SPDX-License-Identifier: MIT
pragma solidity >=0.4.25 <=0.6.10;

import "./interfaces/IAssetDirectory.sol";
import "./interfaces/IDidRegistry.sol";

abstract contract AssetOperatorBase {
    IAssetDirectory public directory;
    IDidRegistry public didRegistry;

    constructor(address directoryAddress, address didRegistryAddress) public {
        require(directoryAddress != address(0), "AssetOperatorBase: zero directory");
        require(didRegistryAddress != address(0), "AssetOperatorBase: zero did registry");
        directory = IAssetDirectory(directoryAddress);
        didRegistry = IDidRegistry(didRegistryAddress);
    }

    function _resolveActiveDid(address account) internal view returns (string memory) {
        return didRegistry.getActiveDid(account);
    }
}
