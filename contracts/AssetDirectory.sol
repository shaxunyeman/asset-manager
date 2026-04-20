// SPDX-License-Identifier: MIT
pragma solidity >=0.4.25 <=0.6.10;

import "./access/Ownable.sol";
import "./libraries/SafeMath.sol";

contract AssetDirectory is Ownable {
    using SafeMath for uint256;

    uint8 public constant STATUS_NORMAL = 0;
    uint8 public constant STATUS_FROZEN = 1;
    uint8 public constant STATUS_DISCARDED = 2;

    /// @notice 资产目录中的核心资产信息。
    /// @param id 资产唯一业务标识。
    /// @param owner 资产当前所有者 DID。
    /// @param metadata 资产元数据，采用 JSON 字符串格式。
    /// @param status 资产生命周期状态，0 表示正常，1 表示冻结，2 表示报废。
    /// @param createTime 资产创建时的区块时间戳。
    struct Asset {
        string id;
        string owner;
        string metadata;
        uint8 status;
        uint256 createTime;
    }

    /// @notice 资产内部记录，附带存在性和授权版本控制信息。
    /// @param asset 持久化存储的资产对象。
    /// @param exists 资产记录是否存在。
    /// @param authorizationEpoch 用于使旧授权失效的授权版本号。
    struct AssetRecord {
        Asset asset;
        bool exists;
        uint256 authorizationEpoch;
    }

    /// @notice 资产针对某个 DID 的内部授权状态。
    /// @param active 该授权是否当前被标记为有效。
    /// @param grantedAt 授权创建时的区块时间戳。
    /// @param epoch 授权写入时对应的资产授权版本号。
    struct AuthorizationRecord {
        bool active;
        uint256 grantedAt;
        uint256 epoch;
    }

    address public registrationManager;
    address public transferManager;
    address public authorizationManager;

    mapping(bytes32 => AssetRecord) private _assets;
    mapping(bytes32 => mapping(bytes32 => AuthorizationRecord)) private _authorizations;

    /// @notice 资产注册管理合约地址更新时触发。
    /// @param previousManager 旧注册管理合约地址。
    /// @param newManager 新注册管理合约地址。
    event RegistrationManagerUpdated(address indexed previousManager, address indexed newManager);

    /// @notice 权属转移管理合约地址更新时触发。
    /// @param previousManager 旧权属转移管理合约地址。
    /// @param newManager 新权属转移管理合约地址。
    event TransferManagerUpdated(address indexed previousManager, address indexed newManager);

    /// @notice 授权管理合约地址更新时触发。
    /// @param previousManager 旧授权管理合约地址。
    /// @param newManager 新授权管理合约地址。
    event AuthorizationManagerUpdated(address indexed previousManager, address indexed newManager);

    /// @notice 资产状态发生变更时触发。
    /// @param assetKey 资产标识的哈希键。
    /// @param assetId 资产唯一业务标识。
    /// @param previousStatus 变更前状态码。
    /// @param newStatus 变更后状态码。
    event AssetStatusUpdated(
        bytes32 indexed assetKey,
        string assetId,
        uint8 previousStatus,
        uint8 newStatus
    );

    modifier onlyRegistrationManager() {
        require(msg.sender == registrationManager, "AssetDirectory: caller is not registry");
        _;
    }

    modifier onlyTransferManager() {
        require(msg.sender == transferManager, "AssetDirectory: caller is not transfer manager");
        _;
    }

    modifier onlyAuthorizationManager() {
        require(
            msg.sender == authorizationManager,
            "AssetDirectory: caller is not authorization manager"
        );
        _;
    }

    /// @notice 设置允许执行资产注册的管理合约。
    /// @param manager 资产注册管理合约地址。
    function setRegistrationManager(address manager) external onlyOwner {
        require(manager != address(0), "AssetDirectory: zero manager");
        emit RegistrationManagerUpdated(registrationManager, manager);
        registrationManager = manager;
    }

    /// @notice 设置允许执行资产权属转移的管理合约。
    /// @param manager 权属转移管理合约地址。
    function setTransferManager(address manager) external onlyOwner {
        require(manager != address(0), "AssetDirectory: zero manager");
        emit TransferManagerUpdated(transferManager, manager);
        transferManager = manager;
    }

    /// @notice 设置允许执行资产授权管理的合约。
    /// @param manager 授权管理合约地址。
    function setAuthorizationManager(address manager) external onlyOwner {
        require(manager != address(0), "AssetDirectory: zero manager");
        emit AuthorizationManagerUpdated(authorizationManager, manager);
        authorizationManager = manager;
    }

    /// @notice 在目录中创建新的资产记录。
    /// @dev 仅允许已配置的资产注册管理合约调用。
    /// @param assetId 资产唯一业务标识。
    /// @param ownerDid 资产初始所有者 DID。
    /// @param metadata 资产元数据，采用 JSON 字符串格式。
    function registerAsset(
        string calldata assetId,
        string calldata ownerDid,
        string calldata metadata
    ) external onlyRegistrationManager {
        require(bytes(assetId).length != 0, "AssetDirectory: empty asset id");
        require(bytes(ownerDid).length != 0, "AssetDirectory: empty owner did");

        bytes32 assetKey = _hash(assetId);
        AssetRecord storage record = _assets[assetKey];

        require(!record.exists, "AssetDirectory: asset exists");

        record.asset = Asset({
            id: assetId,
            owner: ownerDid,
            metadata: metadata,
            status: STATUS_NORMAL,
            createTime: block.timestamp
        });
        record.exists = true;
    }

    /// @notice 从目录中移除已有资产记录。
    /// @dev 仅允许已配置的资产注册管理合约调用。
    /// @param assetId 资产唯一业务标识。
    /// @param ownerDid 发起移除的资产所有者 DID。
    function removeAsset(
        string calldata assetId,
        string calldata ownerDid
    ) external onlyRegistrationManager {
        bytes32 assetKey = _hash(assetId);
        AssetRecord storage record = _requireAsset(assetKey);

        require(_sameString(record.asset.owner, ownerDid), "AssetDirectory: owner mismatch");

        delete record.asset;
        record.exists = false;
        record.authorizationEpoch = record.authorizationEpoch.add(1);
    }

    /// @notice 将资产所有权转移给新的 DID。
    /// @dev 仅允许已配置的权属转移管理合约调用。
    /// @param assetId 资产唯一业务标识。
    /// @param currentOwnerDid 预期的当前所有者 DID。
    /// @param newOwnerDid 转移后的新所有者 DID。
    function transferAssetOwnership(
        string calldata assetId,
        string calldata currentOwnerDid,
        string calldata newOwnerDid
    ) external onlyTransferManager {
        require(bytes(newOwnerDid).length != 0, "AssetDirectory: empty new owner");

        bytes32 assetKey = _hash(assetId);
        AssetRecord storage record = _requireAsset(assetKey);

        require(record.asset.status == STATUS_NORMAL, "AssetDirectory: asset not transferable");
        require(
            _sameString(record.asset.owner, currentOwnerDid),
            "AssetDirectory: current owner mismatch"
        );
        require(
            !_sameString(currentOwnerDid, newOwnerDid),
            "AssetDirectory: owner unchanged"
        );

        record.asset.owner = newOwnerDid;
        record.authorizationEpoch = record.authorizationEpoch.add(1);
    }

    /// @notice 向其他 DID 授予资产使用授权。
    /// @dev 仅允许已配置的授权管理合约调用。
    /// @param assetId 资产唯一业务标识。
    /// @param ownerDid 发起授权的资产所有者 DID。
    /// @param granteeDid 接收授权的 DID。
    function grantAssetAuthorization(
        string calldata assetId,
        string calldata ownerDid,
        string calldata granteeDid
    ) external onlyAuthorizationManager {
        require(bytes(granteeDid).length != 0, "AssetDirectory: empty grantee did");

        bytes32 assetKey = _hash(assetId);
        AssetRecord storage record = _requireAsset(assetKey);

        require(record.asset.status == STATUS_NORMAL, "AssetDirectory: asset not authorizable");
        require(_sameString(record.asset.owner, ownerDid), "AssetDirectory: owner mismatch");
        require(!_sameString(ownerDid, granteeDid), "AssetDirectory: self authorization");

        AuthorizationRecord storage authorization = _authorizations[assetKey][_hash(granteeDid)];
        authorization.active = true;
        authorization.grantedAt = block.timestamp;
        authorization.epoch = record.authorizationEpoch;
    }

    /// @notice 撤销资产对指定 DID 的既有授权。
    /// @dev 仅允许已配置的授权管理合约调用。
    /// @param assetId 资产唯一业务标识。
    /// @param ownerDid 发起撤销的资产所有者 DID。
    /// @param granteeDid 将被撤销授权的 DID。
    function revokeAssetAuthorization(
        string calldata assetId,
        string calldata ownerDid,
        string calldata granteeDid
    ) external onlyAuthorizationManager {
        bytes32 assetKey = _hash(assetId);
        AssetRecord storage record = _requireAsset(assetKey);
        AuthorizationRecord storage authorization = _authorizations[assetKey][_hash(granteeDid)];

        require(_sameString(record.asset.owner, ownerDid), "AssetDirectory: owner mismatch");
        require(
            authorization.active && authorization.epoch == record.authorizationEpoch,
            "AssetDirectory: authorization not active"
        );

        authorization.active = false;
    }

    /// @notice 更新资产生命周期状态。
    /// @dev 当资产状态变为非正常时，既有授权会被整体失效。
    /// @param assetId 资产唯一业务标识。
    /// @param newStatus 目标状态码，0 表示正常，1 表示冻结，2 表示报废。
    function setAssetStatus(string calldata assetId, uint8 newStatus) external onlyOwner {
        require(newStatus <= STATUS_DISCARDED, "AssetDirectory: invalid status");

        bytes32 assetKey = _hash(assetId);
        AssetRecord storage record = _requireAsset(assetKey);
        uint8 previousStatus = record.asset.status;

        require(previousStatus != newStatus, "AssetDirectory: status unchanged");

        record.asset.status = newStatus;
        if (newStatus != STATUS_NORMAL) {
            record.authorizationEpoch = record.authorizationEpoch.add(1);
        }

        emit AssetStatusUpdated(assetKey, record.asset.id, previousStatus, newStatus);
    }

    /// @notice 返回资产当前所有者 DID。
    /// @param assetId 资产唯一业务标识。
    /// @return 资产当前所有者 DID。
    function getAssetOwner(string calldata assetId) external view returns (string memory) {
        bytes32 assetKey = _hash(assetId);
        return _requireAsset(assetKey).asset.owner;
    }

    /// @notice 返回资产当前状态码。
    /// @param assetId 资产唯一业务标识。
    /// @return 资产状态码，0 表示正常，1 表示冻结，2 表示报废。
    function getAssetStatus(string calldata assetId) external view returns (uint8) {
        bytes32 assetKey = _hash(assetId);
        return _requireAsset(assetKey).asset.status;
    }

    /// @notice 检查指定 DID 当前是否对资产拥有有效授权。
    /// @param assetId 资产唯一业务标识。
    /// @param granteeDid 待查询的 DID。
    /// @return 若授权处于有效状态且未被版本失效机制清理，则返回 true。
    function isAssetAuthorized(
        string calldata assetId,
        string calldata granteeDid
    ) external view returns (bool) {
        bytes32 assetKey = _hash(assetId);
        AssetRecord storage record = _assets[assetKey];
        if (!record.exists) {
            return false;
        }

        AuthorizationRecord storage authorization = _authorizations[assetKey][_hash(granteeDid)];
        return authorization.active && authorization.epoch == record.authorizationEpoch;
    }

    /// @notice 返回资产完整数据。
    /// @param assetId 资产唯一业务标识。
    /// @return id 资产标识。
    /// @return ownerDid 当前所有者 DID。
    /// @return metadata 资产元数据 JSON 字符串。
    /// @return status 资产状态码。
    /// @return createTime 资产创建时的区块时间戳。
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
        )
    {
        Asset storage asset = _requireAsset(_hash(assetId)).asset;
        return (asset.id, asset.owner, asset.metadata, asset.status, asset.createTime);
    }

    /// @notice 返回资产针对指定 DID 的授权原始状态。
    /// @param assetId 资产唯一业务标识。
    /// @param granteeDid 待查询的 DID。
    /// @return active 当前授权是否有效。
    /// @return grantedAt 授权创建时的区块时间戳。
    /// @return epoch 该授权记录保存的授权版本号。
    function getAuthorizationState(
        string calldata assetId,
        string calldata granteeDid
    ) external view returns (bool active, uint256 grantedAt, uint256 epoch) {
        bytes32 assetKey = _hash(assetId);
        AssetRecord storage record = _requireAsset(assetKey);
        AuthorizationRecord storage authorization = _authorizations[assetKey][_hash(granteeDid)];
        bool isActive = authorization.active && authorization.epoch == record.authorizationEpoch;
        return (isActive, authorization.grantedAt, authorization.epoch);
    }

    function _requireAsset(bytes32 assetKey) private view returns (AssetRecord storage) {
        AssetRecord storage record = _assets[assetKey];
        require(record.exists, "AssetDirectory: asset not found");
        return record;
    }

    function _hash(string memory value) private pure returns (bytes32) {
        return keccak256(bytes(value));
    }

    function _sameString(string memory left, string memory right) private pure returns (bool) {
        return _hash(left) == _hash(right);
    }
}
