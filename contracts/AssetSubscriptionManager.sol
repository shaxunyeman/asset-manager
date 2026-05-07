pragma solidity >=0.4.25 <=0.6.10;

import "./access/Ownable.sol";
import "./interfaces/IDidRegistry.sol";

contract AssetSubscriptionManager is Ownable {

    struct SubscriptionRecord {
        string id;
        string subscriberDid;
        string metadata;
        uint256 price;
        uint256 subscriptionTime;
        bool exists;
    }

    mapping(bytes32 => SubscriptionRecord) private _subscriptions;

    IDidRegistry public didRegistry;

    event SubscribedAsset(
        bytes32 indexed subscriptionKey,
        string id,
        string metadata,
        address indexed operator,
        uint256 subscriptionTime
    );

    constructor(address didRegistryAddress) public {
        require(didRegistryAddress != address(0), "AssetPublishManager: zero did registry");
        didRegistry = IDidRegistry(didRegistryAddress);
    }

    /// @notice 购买订阅数据资产。
    /// @param id 购买订阅的数据资产唯一业务标识。
    /// @param price 购买订阅的价格。
    /// @param metadata 购买订阅的数据资产元数据，采用 JSON 字符串格式。
    function purchaseSubscriptionOfAsset(string calldata id, uint256 price, string calldata metadata) external {
        require(price > 0, "AssetSubscriptionManager: invalid price");
        require(bytes(id).length != 0, "AssetSubscriptionManager: empty asset id");
        require(bytes(metadata).length != 0, "AssetSubscriptionManager: empty metadata");

        string memory subscriberDid = _resolveActiveDid(msg.sender);
        bytes32 subscriptionKey = keccak256(abi.encodePacked(id, subscriberDid));
        SubscriptionRecord storage record = _subscriptions[subscriptionKey];
        require(!record.exists, "AssetSubscriptionManager: asset already subscribed");

        record.id = id;
        record.subscriberDid = subscriberDid;
        record.metadata = metadata;
        record.price = price;
        record.subscriptionTime = block.timestamp;
        record.exists = true;

        emit SubscribedAsset(subscriptionKey, id, metadata, msg.sender, block.timestamp);
    }

    function _resolveActiveDid(address account) internal view returns (string memory) {
        return didRegistry.getActiveDid(account);
    }

}