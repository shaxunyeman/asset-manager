// SPDX-License-Identifier: MIT
pragma solidity >=0.4.25 <=0.6.10;

import "./AssetOperatorBase.sol";

contract AssetAuthorizationManager is AssetOperatorBase {
    /// @notice 资产授权成功时触发。
    /// @param assetKey 资产标识的哈希键。
    /// @param assetId 资产唯一业务标识。
    /// @param ownerDid 发起授权的资产所有者 DID。
    /// @param granteeDid 被授权的 DID。
    /// @param operator 发起授权交易的链上账户。
    /// @param grantTime 授权发生时的区块时间戳。
    event AssetAuthorizationGranted(
        bytes32 indexed assetKey,
        string assetId,
        string ownerDid,
        string granteeDid,
        address indexed operator,
        uint256 grantTime
    );

    /// @notice 资产授权被撤销时触发。
    /// @param assetKey 资产标识的哈希键。
    /// @param assetId 资产唯一业务标识。
    /// @param ownerDid 发起撤销的资产所有者 DID。
    /// @param granteeDid 被撤销授权的 DID。
    /// @param operator 发起撤销交易的链上账户。
    /// @param revokeTime 撤销发生时的区块时间戳。
    event AssetAuthorizationRevoked(
        bytes32 indexed assetKey,
        string assetId,
        string ownerDid,
        string granteeDid,
        address indexed operator,
        uint256 revokeTime
    );

    constructor(address directoryAddress, address didRegistryAddress)
        public
        AssetOperatorBase(directoryAddress, didRegistryAddress)
    {}

    /// @notice 向其他账户对应的激活 DID 授予资产使用权限。
    /// @param assetId 资产唯一业务标识。
    /// @param granteeAccount 被授权账户，其激活 DID 将获得授权。
    function grantAuthorization(string calldata assetId, address granteeAccount) external {
        require(granteeAccount != address(0), "AssetAuthorizationManager: zero account");

        string memory ownerDid = _resolveActiveDid(msg.sender);
        string memory granteeDid = _resolveActiveDid(granteeAccount);

        directory.grantAssetAuthorization(assetId, ownerDid, granteeDid);

        emit AssetAuthorizationGranted(
            keccak256(bytes(assetId)),
            assetId,
            ownerDid,
            granteeDid,
            msg.sender,
            block.timestamp
        );
    }

    /// @notice 撤销其他账户对应激活 DID 的资产使用权限。
    /// @param assetId 资产唯一业务标识。
    /// @param granteeAccount 被撤销授权的账户，其激活 DID 对应授权将失效。
    function revokeAuthorization(string calldata assetId, address granteeAccount) external {
        require(granteeAccount != address(0), "AssetAuthorizationManager: zero account");

        string memory ownerDid = _resolveActiveDid(msg.sender);
        string memory granteeDid = _resolveActiveDid(granteeAccount);

        directory.revokeAssetAuthorization(assetId, ownerDid, granteeDid);

        emit AssetAuthorizationRevoked(
            keccak256(bytes(assetId)),
            assetId,
            ownerDid,
            granteeDid,
            msg.sender,
            block.timestamp
        );
    }
}
