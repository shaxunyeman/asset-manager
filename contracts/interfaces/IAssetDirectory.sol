// SPDX-License-Identifier: MIT
pragma solidity >=0.4.25 <=0.6.10;

interface IAssetDirectory {
    /// @notice 在资产目录中注册新资产。
    /// @param assetId 资产唯一业务标识。
    /// @param ownerDid 资产初始所有者的 DID。
    /// @param metadata 资产元数据，采用 JSON 字符串格式。
    function registerAsset(
        string calldata assetId,
        string calldata ownerDid,
        string calldata metadata
    ) external;

    /// @notice 转移已注册资产的所有权 DID。
    /// @param assetId 资产唯一业务标识。
    /// @param currentOwnerDid 预期的当前所有者 DID。
    /// @param newOwnerDid 转移后的新所有者 DID。
    function transferAssetOwnership(
        string calldata assetId,
        string calldata currentOwnerDid,
        string calldata newOwnerDid
    ) external;

    /// @notice 向其他 DID 授予资产使用授权。
    /// @param assetId 资产唯一业务标识。
    /// @param ownerDid 发起授权的资产所有者 DID。
    /// @param granteeDid 被授权的 DID。
    function grantAssetAuthorization(
        string calldata assetId,
        string calldata ownerDid,
        string calldata granteeDid
    ) external;

    /// @notice 撤销已授予的资产使用授权。
    /// @param assetId 资产唯一业务标识。
    /// @param ownerDid 发起撤销的资产所有者 DID。
    /// @param granteeDid 将被撤销授权的 DID。
    function revokeAssetAuthorization(
        string calldata assetId,
        string calldata ownerDid,
        string calldata granteeDid
    ) external;

    /// @notice 返回资产当前所有者 DID。
    /// @param assetId 资产唯一业务标识。
    /// @return 资产当前所有者的 DID。
    function getAssetOwner(string calldata assetId) external view returns (string memory);

    /// @notice 返回资产当前状态码。
    /// @param assetId 资产唯一业务标识。
    /// @return 资产状态码，0 表示正常，1 表示冻结，2 表示报废。
    function getAssetStatus(string calldata assetId) external view returns (uint8);

    /// @notice 检查指定 DID 当前是否对资产拥有有效授权。
    /// @param assetId 资产唯一业务标识。
    /// @param granteeDid 待查询的 DID。
    /// @return 若 DID 对该资产存在有效授权则返回 true，否则返回 false。
    function isAssetAuthorized(
        string calldata assetId,
        string calldata granteeDid
    ) external view returns (bool);

    /// @notice 返回资产完整信息。
    /// @param assetId 资产唯一业务标识。
    /// @return id 资产标识。
    /// @return ownerDid 当前所有者 DID。
    /// @return metadata 资产元数据 JSON 字符串。
    /// @return status 资产状态码。
    /// @return createTime 资产创建时间戳。
    function getAsset(
        string calldata assetId
    )
        external
        view
        returns (
            string memory id,
            string memory ownerDid,
            string memory metadata,
            uint8 status,
            uint256 createTime
        );
}
