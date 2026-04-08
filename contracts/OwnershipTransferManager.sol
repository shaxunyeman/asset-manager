// SPDX-License-Identifier: MIT
pragma solidity >=0.4.25 <=0.6.10;

import "./AssetOperatorBase.sol";

contract OwnershipTransferManager is AssetOperatorBase {
    /// @notice 资产权属转移成功时触发。
    /// @param assetKey 资产标识的哈希键。
    /// @param assetId 资产唯一业务标识。
    /// @param previousOwnerDid 转移前所有者 DID。
    /// @param newOwnerDid 转移后所有者 DID。
    /// @param operator 发起转移交易的链上账户。
    /// @param transferTime 转移发生时的区块时间戳。
    event AssetOwnershipTransferred(
        bytes32 indexed assetKey,
        string assetId,
        string previousOwnerDid,
        string newOwnerDid,
        address indexed operator,
        uint256 transferTime
    );

    constructor(address directoryAddress, address didRegistryAddress)
        public
        AssetOperatorBase(directoryAddress, didRegistryAddress)
    {}

    /// @notice 将资产从调用方 DID 转移给另一个账户对应的激活 DID。
    /// @param assetId 资产唯一业务标识。
    /// @param newOwnerAccount 目标接收方账户，其激活 DID 将成为新所有者。
    function transferAssetOwnership(string calldata assetId, address newOwnerAccount) external {
        require(newOwnerAccount != address(0), "OwnershipTransferManager: zero account");

        string memory currentOwnerDid = _resolveActiveDid(msg.sender);
        string memory newOwnerDid = _resolveActiveDid(newOwnerAccount);

        directory.transferAssetOwnership(assetId, currentOwnerDid, newOwnerDid);

        emit AssetOwnershipTransferred(
            keccak256(bytes(assetId)),
            assetId,
            currentOwnerDid,
            newOwnerDid,
            msg.sender,
            block.timestamp
        );
    }
}
