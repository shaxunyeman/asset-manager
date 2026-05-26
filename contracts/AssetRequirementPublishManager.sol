// SPDX-License-Identifier: MIT
pragma solidity >=0.4.25 <=0.6.10;

import "./access/Ownable.sol";
import "./interfaces/IDidRegistry.sol";

contract AssetRequirementPublishManager is Ownable {
    uint8 public constant STATUS_NORMAL = 1;    // 正常
    uint8 public constant STATUS_OFFLINE = 2;   // 下架

    struct PublishedRequirementRecord {
        string id;
        string publisherDid;
        string metadata;
        uint8 status;
        uint256 publishTime;
        bool exists;
    }

    IDidRegistry public didRegistry;

    mapping(bytes32 => PublishedRequirementRecord) private _publishedRequirements;

    /// @notice 数据需求发布时触发。
    /// @param requirementKey 需求发布的哈希键。
    /// @param id 需求发布唯一业务标识。
    /// @param publisherDid 需求发布者 DID。
    /// @param metadata 需求发布元数据，采用 JSON 字符串格式。
    /// @param operator 发起发布需求的链上账户。
    /// @param createTime 发布发生时的区块时间戳。
    event PublishedRequirement(
        bytes32 indexed requirementKey,
        string id,
        string publisherDid,
        string metadata,
        address indexed operator,
        uint256 createTime
    );

    /// @notice 数据需求发布状态变更时触发。
    /// @param requirementKey 需求发布的哈希键。
    /// @param status 状态, 1:正常 2:下架
    /// @param statusMsg 状态说明，比如下架原因
    /// @param changedTime 状态变更发生时的区块时间戳。
    event PublishedRequirementStatusChanged(
        bytes32 indexed requirementKey,
        int status,
        string statusMsg,
        uint256 changedTime
    );

    /// @notice 数据需求提供时触发。
    /// @param requirementKey 需求发布的哈希键。
    /// @param requirementId 需求发布唯一业务标识。
    /// @param publishedId 资产发布标识。
    /// @param operator 发起提供需求的链上账户。
    /// @param createTime 提供发生时的区块时间戳。
    event DataRequirementProvided(
        bytes32 indexed requirementKey,
        string requirementId,
        string publishedId,
        address indexed operator,
        uint256 createTime
    );

    constructor(address didRegistryAddress) public {
        require(didRegistryAddress != address(0), "AssetPublishManager: zero did registry");
        didRegistry = IDidRegistry(didRegistryAddress);
    }

    /// @notice 发布数据资产。
    /// @param id 需求发布唯一业务标识。
    /// @param metadata 需求发布元数据，采用 JSON 字符串格式。
    function publishRequirement(string calldata id, string calldata metadata) external {
        require(bytes(id).length != 0, "AssetRequirementPublishManager: empty requirement id");
        require(bytes(metadata).length != 0, "AssetRequirementPublishManager: empty metadata");

        bytes32 requirementKey = _hash(id);
        PublishedRequirementRecord storage record = _publishedRequirements[requirementKey];
        require(!record.exists, "AssetRequirementPublishManager: requirement already published");

        string memory publisherDid = _resolveActiveDid(msg.sender);

        record.id = id;
        record.publisherDid = publisherDid;
        record.metadata = metadata;
        record.status = STATUS_NORMAL;
        record.publishTime = block.timestamp;
        record.exists = true;

        emit PublishedRequirement(
            requirementKey,
            id,
            publisherDid,
            metadata,
            msg.sender,
            block.timestamp
        );
    }

    /// @notice 修改发布数据需求状态。
    /// @param id 需求发布唯一业务标识。
    /// @param status 状态, 1:正常 2:下架
    /// @param statusMsg 状态说明，比如下架原因
    function setPublishedRequirementStatus(string calldata id, int status, string calldata statusMsg) external {
        require(status >= 0 && status <= int256(uint256(STATUS_OFFLINE)), "AssetRequirementPublishManager: invalid status");

        bytes32 requirementKey = _hash(id);
        PublishedRequirementRecord storage record = _requirePublishedRequirement(requirementKey);
        uint8 newStatus = uint8(status);
        uint8 previousStatus = record.status;

        require(previousStatus != newStatus, "AssetRequirementPublishManager: status unchanged");

        record.status = newStatus;

        emit PublishedRequirementStatusChanged(requirementKey, status, statusMsg, block.timestamp);
    }

    /// @notice 提供数据需求。
    /// @param id 需求发布唯一业务标识。
    /// @param publishedId 资产发布标识。
    function provideDataRequirement(string calldata id, string calldata publishedId) external {
        require(bytes(id).length != 0, "AssetRequirementPublishManager: empty requirement id");
        require(bytes(publishedId).length != 0, "AssetRequirementPublishManager: empty published id");

        bytes32 requirementKey = _hash(id);
        PublishedRequirementRecord storage record = _requirePublishedRequirement(requirementKey);
        require(record.status == STATUS_NORMAL, "AssetRequirementPublishManager: requirement not published");

        emit DataRequirementProvided(requirementKey, id, publishedId, msg.sender, block.timestamp);
    }

    function _requirePublishedRequirement(bytes32 requirementKey) private view returns (PublishedRequirementRecord storage) {
        PublishedRequirementRecord storage record = _publishedRequirements[requirementKey];
        require(record.exists, "AssetRequirementPublishManager: requirement not found");
        return record;
    }

    function _resolveActiveDid(address account) internal view returns (string memory) {
        return didRegistry.getActiveDid(account);
    }

    function _hash(string memory value) private pure returns (bytes32) {
        return keccak256(bytes(value));
    }
}
