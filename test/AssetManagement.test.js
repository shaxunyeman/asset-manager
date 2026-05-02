const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Asset management suite", function () {
  let owner;
  let alice;
  let bob;
  let carol;

  let didRegistry;
  let directory;
  let registrationManager;
  let transferManager;
  let authorizationManager;
  let publishManager;

  async function expectRevert(promise, expectedMessage) {
    try {
      await promise;
      expect.fail("Expected transaction to revert");
    } catch (error) {
      expect(error.message).to.include(expectedMessage);
    }
  }

  beforeEach(async function () {
    [owner, alice, bob, carol] = await ethers.getSigners();

    const DidRegistry = await ethers.getContractFactory("DidRegistry");
    didRegistry = await DidRegistry.deploy();
    await didRegistry.deployed();

    const AssetDirectory = await ethers.getContractFactory("AssetDirectory");
    directory = await AssetDirectory.deploy();
    await directory.deployed();

    const AssetRegistrationManager = await ethers.getContractFactory("AssetRegistrationManager");
    registrationManager = await AssetRegistrationManager.deploy(directory.address, didRegistry.address);
    await registrationManager.deployed();

    const OwnershipTransferManager = await ethers.getContractFactory("OwnershipTransferManager");
    transferManager = await OwnershipTransferManager.deploy(directory.address, didRegistry.address);
    await transferManager.deployed();

    const AssetAuthorizationManager = await ethers.getContractFactory("AssetAuthorizationManager");
    authorizationManager = await AssetAuthorizationManager.deploy(directory.address, didRegistry.address);
    await authorizationManager.deployed();

    const AssetPublishManager = await ethers.getContractFactory("AssetPublishManager");
    publishManager = await AssetPublishManager.deploy(didRegistry.address);
    await publishManager.deployed();

    await directory.setRegistrationManager(registrationManager.address);
    await directory.setTransferManager(transferManager.address);
    await directory.setAuthorizationManager(authorizationManager.address);

    await didRegistry.bindDid(alice.address, "did:example:alice");
    await didRegistry.bindDid(bob.address, "did:example:bob");
    await didRegistry.bindDid(carol.address, "did:example:carol");
  });

  it("registers an asset and stores the owner DID", async function () {
    const metadata = '{"name":"device-1"}';
    const tx = await registrationManager.connect(alice).registerAsset("asset-001", metadata);
    const receipt = await tx.wait();
    expect(receipt.events.some((event) => event.event === "AssetRegistered")).to.equal(true);

    const asset = await directory.getAsset("asset-001");
    expect(asset.id).to.equal("asset-001");
    expect(asset.ownerDid).to.equal("did:example:alice");
    expect(asset.metadata).to.equal(metadata);
    expect(asset.status).to.equal(0);
  });

  it("transfers ownership and invalidates previous authorizations", async function () {
    await registrationManager.connect(alice).registerAsset("asset-001", '{"name":"device-1"}');
    await authorizationManager.connect(alice).grantAuthorization("asset-001", bob.address, '{"name": "test-1"}');
    await authorizationManager.connect(bob).acceptAuthorizationRequest("asset-001");
    expect(await directory.isAssetAuthorized("asset-001", "did:example:bob")).to.equal(true);

    const tx = await transferManager.connect(alice).transferAssetOwnership("asset-001", carol.address);
    const receipt = await tx.wait();
    expect(receipt.events.some((event) => event.event === "AssetOwnershipTransferred")).to.equal(
      true
    );

    expect(await directory.getAssetOwner("asset-001")).to.equal("did:example:carol");
    expect(await directory.isAssetAuthorized("asset-001", "did:example:bob")).to.equal(false);
  });

  it("removes an asset and invalidates previous authorizations", async function () {
    await registrationManager.connect(alice).registerAsset("asset-001", '{"name":"device-1"}');
    await authorizationManager.connect(alice).grantAuthorization("asset-001", bob.address, '{"name": "test-1"}');
    await authorizationManager.connect(bob).acceptAuthorizationRequest("asset-001");

    const tx = await registrationManager.connect(alice).removeAsset("asset-001");
    const receipt = await tx.wait();
    expect(receipt.events.some((event) => event.event === "AssetRemoved")).to.equal(true);

    expect(await directory.isAssetAuthorized("asset-001", "did:example:bob")).to.equal(false);
    await expectRevert(directory.getAsset("asset-001"), "AssetDirectory: asset not found");

    await registrationManager.connect(alice).registerAsset("asset-001", '{"name":"device-2"}');
    expect(await directory.isAssetAuthorized("asset-001", "did:example:bob")).to.equal(false);
  });

  it("creates an authorization request and grants only after grantee acceptance", async function () {
    await registrationManager.connect(alice).registerAsset("asset-001", '{"name":"device-1"}');

    let tx = await authorizationManager.connect(alice).grantAuthorization("asset-001", bob.address, '{"name": "test-1"}');
    let receipt = await tx.wait();
    expect(receipt.events.some((event) => event.event === "AssetAuthorizationRequested")).to.equal(
      true
    );

    let request = await authorizationManager.getAuthorizationRequest("asset-001", bob.address);
    expect(request.pending).to.equal(true);
    expect(request.ownerDid).to.equal("did:example:alice");
    expect(request.granteeDid).to.equal("did:example:bob");
    expect(await directory.isAssetAuthorized("asset-001", "did:example:bob")).to.equal(false);

    tx = await authorizationManager.connect(bob).acceptAuthorizationRequest("asset-001");
    receipt = await tx.wait();
    expect(receipt.events.some((event) => event.event === "AssetAuthorizationGranted")).to.equal(
      true
    );

    request = await authorizationManager.getAuthorizationRequest("asset-001", bob.address);
    expect(request.pending).to.equal(false);
    expect(await directory.isAssetAuthorized("asset-001", "did:example:bob")).to.equal(true);

    tx = await authorizationManager.connect(alice).revokeAuthorization("asset-001", bob.address);
    receipt = await tx.wait();
    expect(receipt.events.some((event) => event.event === "AssetAuthorizationRevoked")).to.equal(
      true
    );

    expect(await directory.isAssetAuthorized("asset-001", "did:example:bob")).to.equal(false);
  });

  it("allows grantee to reject an authorization request", async function () {
    await registrationManager.connect(alice).registerAsset("asset-001", '{"name":"device-1"}');
    await authorizationManager.connect(alice).grantAuthorization("asset-001", bob.address, '{"name": "test-1"}');

    const tx = await authorizationManager.connect(bob).rejectAuthorizationRequest("asset-001");
    const receipt = await tx.wait();
    expect(receipt.events.some((event) => event.event === "AssetAuthorizationRejected")).to.equal(
      true
    );

    const request = await authorizationManager.getAuthorizationRequest("asset-001", bob.address);
    expect(request.pending).to.equal(false);
    expect(await directory.isAssetAuthorized("asset-001", "did:example:bob")).to.equal(false);
  });

  it("blocks responses from accounts that are not the requested grantee", async function () {
    await registrationManager.connect(alice).registerAsset("asset-001", '{"name":"device-1"}');
    await authorizationManager.connect(alice).grantAuthorization("asset-001", bob.address, '{"name": "test-1"}');

    await expectRevert(
      authorizationManager.connect(carol).acceptAuthorizationRequest("asset-001"),
      "AssetAuthorizationManager: request not found"
    );
  });

  it("blocks duplicate pending authorization requests", async function () {
    await registrationManager.connect(alice).registerAsset("asset-001", '{"name":"device-1"}');
    await authorizationManager.connect(alice).grantAuthorization("asset-001", bob.address, '{"name": "test-1"}');

    await expectRevert(
      authorizationManager.connect(alice).grantAuthorization("asset-001", bob.address, '{"name": "test-1"}'),
      "AssetAuthorizationManager: request already pending"
    );
  });

  it("blocks grantee response after grantee DID changes", async function () {
    await registrationManager.connect(alice).registerAsset("asset-001", '{"name":"device-1"}');
    await authorizationManager.connect(alice).grantAuthorization("asset-001", bob.address, '{"name": "test-1"}');
    await didRegistry.bindDid(bob.address, "did:example:bob:new");

    await expectRevert(
      authorizationManager.connect(bob).acceptAuthorizationRequest("asset-001"),
      "AssetAuthorizationManager: grantee DID changed"
    );
  });

  it("blocks non-owner transfers", async function () {
    await registrationManager.connect(alice).registerAsset("asset-001", '{"name":"device-1"}');

    await expectRevert(
      transferManager.connect(bob).transferAssetOwnership("asset-001", carol.address)
      ,
      "AssetDirectory: current owner mismatch"
    );
  });

  it("blocks non-owner removal", async function () {
    await registrationManager.connect(alice).registerAsset("asset-001", '{"name":"device-1"}');

    await expectRevert(
      registrationManager.connect(bob).removeAsset("asset-001"),
      "AssetDirectory: owner mismatch"
    );
  });

  it("blocks authorization on frozen assets", async function () {
    await registrationManager.connect(alice).registerAsset("asset-001", '{"name":"device-1"}');
    await directory.setAssetStatus("asset-001", 1);

    await expectRevert(
      authorizationManager.connect(alice).grantAuthorization("asset-001", bob.address, '{"name": "test-1"}'),
      "AssetDirectory: asset not authorizable"
    );
  });

  it("publishes an asset and allows owner-managed status changes", async function () {
    const metadata = '{"name":"data-asset-1"}';
    let tx = await publishManager.connect(alice).publishAsset("pub-001", metadata);
    let receipt = await tx.wait();
    expect(receipt.events.some((event) => event.event === "PublishedAsset")).to.equal(true);

    let published = await publishManager.getPublishedAsset("pub-001");
    expect(published.assetId).to.equal("pub-001");
    expect(published.publisherDid).to.equal("did:example:alice");
    expect(published.metadata).to.equal(metadata);
    expect(published.status).to.equal(0);

    tx = await publishManager.setPublishedAssetStatus("pub-001", 1);
    receipt = await tx.wait();
    expect(receipt.events.some((event) => event.event === "PublishedAssetStatusChanged")).to.equal(
      true
    );

    expect(await publishManager.getPublishedAssetStatus("pub-001")).to.equal(1);
  });

  it("blocks duplicate publish and invalid status changes", async function () {
    await publishManager.connect(alice).publishAsset("pub-001", '{"name":"data-asset-1"}');

    await expectRevert(
      publishManager.connect(alice).publishAsset("pub-001", '{"name":"data-asset-1"}'),
      "AssetPublishManager: asset already published"
    );

    await expectRevert(
      publishManager.connect(alice).setPublishedAssetStatus("pub-001", 4),
      "Ownable: caller is not the owner"
    );

    await expectRevert(
      publishManager.connect(owner).setPublishedAssetStatus("pub-001", 4),
      "AssetPublishManager: invalid status"
    );
  });
});
