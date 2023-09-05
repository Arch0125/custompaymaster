import { fillAndSign } from "../src/account-abstraction/test/UserOp";
import { HttpRpcClient, SimpleAccountAPI } from "@account-abstraction/sdk";
import PaymasterArtifact from "../artifacts/contracts/CustomERC20Paymaster.sol/CustomERC20Paymaster.json";
import TestTokenArtifact from "../artifacts/contracts/TestToken.sol/TestToken.json";
import { ethers } from "ethers";
import { expect } from "chai";

describe("CustomERC20Paymaster", function () {
  const mnemonic =
    "test test test test test test test test test test test junk";
  const provider = ethers.getDefaultProvider("http://127.0.0.1:8545");

  const pvtkey1 = ethers.Wallet.fromMnemonic(
    mnemonic,
    "m/44'/60'/0'/0/0"
  ).privateKey;
  const pvtkey2 = ethers.Wallet.fromMnemonic(
    mnemonic,
    "m/44'/60'/0'/0/1"
  ).privateKey;

  const wallet1 = new ethers.Wallet(pvtkey1, provider);
  const wallet2 = new ethers.Wallet(pvtkey2, provider);

  const entryPointAddress = "0x07882Ae1ecB7429a84f1D53048d35c4bB2056877";

  let custompaymaster: any;
  let token1: any;
  let token2: any;
  let scw1: any;
  let scw2: any;

  it("Should deploy CustomERC20Paymaster", async function () {
    const customPaymasterContract = new ethers.ContractFactory(
      PaymasterArtifact.abi,
      PaymasterArtifact.bytecode,
      wallet1
    );

    custompaymaster = await customPaymasterContract.deploy(
      "0x7aD823A5cA21768a3D3041118Bc6e981B0e4D5ee"
    );

    console.log(`CustomPaymaster deployed to ${custompaymaster.address}`);
    expect(custompaymaster.address).to.not.equal(null);
  });

  it("should deploy two erc20 tokens", async function () {
    //deploy two tokens first
    const testTokenContract = new ethers.ContractFactory(
      TestTokenArtifact.abi,
      TestTokenArtifact.bytecode,
      wallet1
    );

    token1 = await testTokenContract.deploy("TestToken1", "TT1");
    token2 = await testTokenContract.deploy("TestToken2", "TT2");

    console.log(`TestToken1 deployed to ${token1.address}`);
    console.log(`TestToken2 deployed to ${token2.address}`);

    expect(token1.address).to.not.equal(null);
    expect(token2.address).to.not.equal(null);
    expect(await token1.balanceOf(wallet1.address)).to.equal(
      "1000000000000000000000000"
    );
    expect(await token2.balanceOf(wallet1.address)).to.equal(
      "1000000000000000000000000"
    );
  });

  it("should allow tokens to custompaymaster", async function () {
    await custompaymaster.addToken(token1.address, "10");

    await custompaymaster.deposit({
      value: ethers.utils.parseEther("10"),
    });
  });

  it("should create scw account", async function () {
    scw1 = new SimpleAccountAPI({
      provider,
      entryPointAddress: "0x7aD823A5cA21768a3D3041118Bc6e981B0e4D5ee",
      owner: wallet1,
      factoryAddress: "0x3647fABd9F0a8CF5CCd9246Cd559BB2E40a8c43F",
    });

    await wallet1.sendTransaction({
      to: await scw1.getAccountAddress(),
      value: ethers.utils.parseEther("10"),
    });

    await token1
      .connect(wallet1)
      .transfer(
        await scw1.getAccountAddress(),
        ethers.utils.parseEther("1000")
      );

    expect(await scw1.getAccountAddress()).to.not.equal(null);
  });

  it("should approve erc20 token to custompaymaster", async function () {
    const preERC20Balance = await token1.balanceOf(
      await scw1.getAccountAddress()
    );

    const tokenApprovePaymaster = await token1.populateTransaction
      .approve(custompaymaster.address, ethers.constants.MaxUint256)
      .then((tx: { data: any }) => tx.data!);
    const execApprove = await scw1.encodeExecute(
      token1.address,
      0,
      tokenApprovePaymaster
    );

    const userOp1 = await scw1.createUnsignedUserOp({
      target: token1.address,
      data: tokenApprovePaymaster,
    });

    userOp1.callData = execApprove;
    userOp1.preVerificationGas = 1000000;
    userOp1.paymasterAndData = ethers.utils.hexConcat([
      custompaymaster.address,
      token1.address,
    ]);

    const client = new HttpRpcClient(
      "http://localhost:3000/rpc",
      "0x7aD823A5cA21768a3D3041118Bc6e981B0e4D5ee",
      31337
    );

    const signedUserOp1 = await scw1.signUserOp(userOp1);

    expect(signedUserOp1).to.not.equal(null);

    console.log(await client.sendUserOpToBundler(signedUserOp1));

    const postERC20Balance = await token1.balanceOf(
      await scw1.getAccountAddress()
    );

    expect(postERC20Balance).to.lessThan(preERC20Balance);
  });

  it("should submit an user operation", async function () {
    const preERC20Balance = await provider.getBalance(wallet2.address);

    const userOp = await scw1.createUnsignedUserOp({
      target: wallet2.address,
      data: "0x",
    });

    const execData = await scw1.encodeExecute(wallet2.address, ethers.utils.parseEther("10"), "0x");

    userOp.preVerificationGas = 1000000;
    userOp.callData = execData;
    userOp.paymasterAndData = ethers.utils.hexConcat([
      custompaymaster.address,
      token1.address,
    ]);

    const rpcClient = new HttpRpcClient(
      "http://localhost:3000/rpc",
      "0x7aD823A5cA21768a3D3041118Bc6e981B0e4D5ee",
      31337
    );

    const signedUserOp = await scw1.signUserOp(userOp);

    await rpcClient.sendUserOpToBundler(signedUserOp);

    const postERC20Balance = await provider.getBalance(wallet2.address);
    expect(postERC20Balance).to.greaterThan(preERC20Balance);
  });
});
