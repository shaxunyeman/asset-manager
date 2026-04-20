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
    await authorizationManager.connect(alice).grantAuthorization("asset-001", bob.address);
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
    await authorizationManager.connect(alice).grantAuthorization("asset-001", bob.address);

    const tx = await registrationManager.connect(alice).removeAsset("asset-001");
    const receipt = await tx.wait();
    expect(receipt.events.some((event) => event.event === "AssetRemoved")).to.equal(true);

    expect(await directory.isAssetAuthorized("asset-001", "did:example:bob")).to.equal(false);
    await expectRevert(directory.getAsset("asset-001"), "AssetDirectory: asset not found");

    await registrationManager.connect(alice).registerAsset("asset-001", '{"name":"device-2"}');
    expect(await directory.isAssetAuthorized("asset-001", "did:example:bob")).to.equal(false);
  });

  it("allows owner to grant and revoke authorization", async function () {
    await registrationManager.connect(alice).registerAsset("asset-001", '{"name":"device-1"}');

    let tx = await authorizationManager.connect(alice).grantAuthorization("asset-001", bob.address);
    let receipt = await tx.wait();
    expect(receipt.events.some((event) => event.event === "AssetAuthorizationGranted")).to.equal(
      true
    );

    expect(await directory.isAssetAuthorized("asset-001", "did:example:bob")).to.equal(true);

    tx = await authorizationManager.connect(alice).revokeAuthorization("asset-001", bob.address);
    receipt = await tx.wait();
    expect(receipt.events.some((event) => event.event === "AssetAuthorizationRevoked")).to.equal(
      true
    );

    expect(await directory.isAssetAuthorized("asset-001", "did:example:bob")).to.equal(false);
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
      authorizationManager.connect(alice).grantAuthorization("asset-001", bob.address),
      "AssetDirectory: asset not authorizable"
    );
  });
});
