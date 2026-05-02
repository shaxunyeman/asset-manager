// SPDX-License-Identifier: MIT
pragma solidity >=0.4.25 <=0.6.10;

import "./access/Ownable.sol";
import "./interfaces/IDidRegistry.sol";

contract AssetPublishManager is Ownable {
    uint8 public constant STATUS_PENDING = 0;
    uint8 public constant STATUS_APPROVED = 1;
    uint8 public constant STATUS_REJECTED = 2;
    uint8 public constant STATUS_OFFLINE = 3;

    struct PublishedAssetRecord {
        string id;
        string publisherDid;
        string metadata;
        uint8 status;
        uint256 publishTime;
        bool exists;
    }

    IDidRegistry public didRegistry;

    mapping(bytes32 => PublishedAssetRecord) private _publishedAssets;

    /// @notice 数据资产发布时触发。
    /// @param assetKey 资产发布的哈希键。
    /// @param id 资产发布唯一业务标识。
    /// @param publisherDid 资产发布者 DID。
    /// @param metadata 资产发布元数据，采用 JSON 字符串格式。
    /// @param operator 发起发布交易的链上账户。
    /// @param createTime 发布发生时的区块时间戳。
    event PublishedAsset(
        bytes32 indexed assetKey,
        string id,
        string publisherDid,
        string metadata,
        address indexed operator,
        uint256 createTime
    );

    /// @notice 数据资产发布状态变更时触发。
    /// @param assetKey 资产发布的哈希键。
    /// @param status 审核状态, 0:待审核 1:审核通过 2:审核失败 3:下架
    /// @param changedTime 状态变更发生时的区块时间戳。
    event PublishedAssetStatusChanged(
        bytes32 indexed assetKey,
        int status,
        uint256 changedTime
    );

    constructor(address didRegistryAddress) public {
        require(didRegistryAddress != address(0), "AssetPublishManager: zero did registry");
        didRegistry = IDidRegistry(didRegistryAddress);
    }

    /// @notice 发布数据资产。
    /// @param id 资产发布唯一业务标识。
    /// @param metadata 资产发布元数据，采用 JSON 字符串格式。
    function publishAsset(string calldata id, string calldata metadata) external {
        require(bytes(id).length != 0, "AssetPublishManager: empty asset id");
        require(bytes(metadata).length != 0, "AssetPublishManager: empty metadata");

        bytes32 assetKey = _hash(id);
        PublishedAssetRecord storage record = _publishedAssets[assetKey];
        require(!record.exists, "AssetPublishManager: asset already published");

        string memory publisherDid = _resolveActiveDid(msg.sender);

        record.id = id;
        record.publisherDid = publisherDid;
        record.metadata = metadata;
        record.status = STATUS_PENDING;
        record.publishTime = block.timestamp;
        record.exists = true;

        emit PublishedAsset(
            assetKey,
            id,
            publisherDid,
            metadata,
            msg.sender,
            block.timestamp
        );
    }

    /// @notice 修改发布数据资产状态。
    /// @param id 资产发布唯一业务标识。
    /// @param status 审核状态, 0:待审核 1:审核通过 2:审核失败 3:下架
    function setPublishedAssetStatus(string calldata id, int status) external onlyOwner {
        require(status >= 0 && status <= int256(uint256(STATUS_OFFLINE)), "AssetPublishManager: invalid status");

        bytes32 assetKey = _hash(id);
        PublishedAssetRecord storage record = _requirePublishedAsset(assetKey);
        uint8 newStatus = uint8(status);
        uint8 previousStatus = record.status;

        require(previousStatus != newStatus, "AssetPublishManager: status unchanged");

        record.status = newStatus;

        emit PublishedAssetStatusChanged(assetKey, status, block.timestamp);
    }

    /// @notice 查询已发布资产的完整信息。
    /// @param id 资产发布唯一业务标识。
    /// @return assetId 资产标识。
    /// @return publisherDid 发布者 DID。
    /// @return metadata 发布元数据。
    /// @return status 当前状态码。
    /// @return publishTime 发布时间戳。
    function getPublishedAsset(
        string calldata id
    )
        external
        view
        returns (
            string memory assetId,
            string memory publisherDid,
            string memory metadata,
            uint8 status,
            uint256 publishTime
        )
    {
        PublishedAssetRecord storage record = _requirePublishedAsset(_hash(id));
        return (record.id, record.publisherDid, record.metadata, record.status, record.publishTime);
    }

    /// @notice 查询已发布资产当前状态。
    /// @param id 资产发布唯一业务标识。
    /// @return status 当前状态码。
    function getPublishedAssetStatus(string calldata id) external view returns (uint8 status) {
        return _requirePublishedAsset(_hash(id)).status;
    }

    /// @notice 检查资产是否已经发布。
    /// @param id 资产发布唯一业务标识。
    /// @return 若资产已发布则返回 true，否则返回 false。
    function isPublishedAsset(string calldata id) external view returns (bool) {
        return _publishedAssets[_hash(id)].exists;
    }

    /// @notice 返回指定资产发布者的 DID。
    /// @param id 资产发布唯一业务标识。
    /// @return 发布者 DID。
    function getPublishedAssetPublisher(string calldata id) external view returns (string memory) {
        return _requirePublishedAsset(_hash(id)).publisherDid;
    }

    function _requirePublishedAsset(bytes32 assetKey)
        private
        view
        returns (PublishedAssetRecord storage record)
    {
        record = _publishedAssets[assetKey];
        require(record.exists, "AssetPublishManager: asset not found");
    }

    function _resolveActiveDid(address account) internal view returns (string memory) {
        return didRegistry.getActiveDid(account);
    }

    function _hash(string memory value) private pure returns (bytes32) {
        return keccak256(bytes(value));
    }
}
