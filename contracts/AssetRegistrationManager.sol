// SPDX-License-Identifier: MIT
pragma solidity >=0.4.25 <=0.6.10;

import "./AssetOperatorBase.sol";

contract AssetRegistrationManager is AssetOperatorBase {
    /// @notice 新资产注册成功时触发。
    /// @param assetKey 资产标识的哈希键。
    /// @param assetId 资产唯一业务标识。
    /// @param ownerDid 资产所有者 DID。
    /// @param operator 发起注册交易的链上账户。
    /// @param createTime 注册发生时的区块时间戳。
    event AssetRegistered(
        bytes32 indexed assetKey,
        string assetId,
        string ownerDid,
        address indexed operator,
        uint256 createTime
    );

    constructor(address directoryAddress, address didRegistryAddress)
        public
        AssetOperatorBase(directoryAddress, didRegistryAddress)
    {}

    /// @notice 以调用方当前激活 DID 注册新资产。
    /// @param assetId 资产唯一业务标识。
    /// @param metadata 资产元数据，采用 JSON 字符串格式。
    function registerAsset(string calldata assetId, string calldata metadata) external {
        string memory ownerDid = _resolveActiveDid(msg.sender);
        directory.registerAsset(assetId, ownerDid, metadata);
        emit AssetRegistered(
            keccak256(bytes(assetId)),
            assetId,
            ownerDid,
            msg.sender,
            block.timestamp
        );
    }
}
