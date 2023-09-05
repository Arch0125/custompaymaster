import { fillAndSign } from "./account-abstraction/test/UserOp";
import { HttpRpcClient, SimpleAccountAPI } from "@account-abstraction/sdk";
import { ethers } from "ethers";
import PaymasterArtifact from "../artifacts/contracts/CustomERC20Paymaster.sol/CustomERC20Paymaster.json";
import TestTokenArtifact from "../artifacts/contracts/TestToken.sol/TestToken.json";
import { SimpleAccount } from "./account-abstraction/typechain";

async function main() {
  const mnemonic =
    "test test test test test test test test test test test junk";
  const provider = ethers.getDefaultProvider("http://127.0.0.1:8545");

  let account: SimpleAccount;

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

  const paymasterABI = PaymasterArtifact.abi;
  const paymasterContract = new ethers.Contract(
    "0x776D6996c8180838dC0587aE0DE5D614b1350f37",
    paymasterABI,
    wallet1
  );
  const testToken = new ethers.Contract(
    "0xf93b0549cD50c849D792f0eAE94A598fA77C7718",
    TestTokenArtifact.abi,
    wallet1
  );

  await testToken.approve(
    paymasterContract.address,
    ethers.utils.parseEther("1000000")
  );

  await paymasterContract.deposit({
    value: ethers.utils.parseEther("10"),
  });

  await paymasterContract.addToken(testToken.address, "10");

  const scw1 = new SimpleAccountAPI({
    provider,
    entryPointAddress: "0x7aD823A5cA21768a3D3041118Bc6e981B0e4D5ee",
    owner: wallet1,
    factoryAddress: "0x3647fABd9F0a8CF5CCd9246Cd559BB2E40a8c43F",
  });

  // await testToken.mint(await scw1.getAccountAddress(), ethers.utils.parseEther("1000000"));

  console.log(
    "ERC20 Balance before userOp : ",
    (await testToken.balanceOf(await scw1.getAccountAddress())).toString()
  );
  console.log(
    "Native Balance before userOp : ",
    (await provider.getBalance(await scw1.getAccountAddress())).toString()
  );
  console.log(
    "Paymaster Native Balance before userOp : ",
    (await provider.getBalance(paymasterContract.address)).toString()
  );

  const tokenApprovePaymaster = await testToken.populateTransaction
    .approve(paymasterContract.address, ethers.constants.MaxUint256)
    .then((tx) => tx.data!);
  const execApprove = await scw1.encodeExecute(
    testToken.address,
    0,
    tokenApprovePaymaster
  );

  console.log("tokenApprovePaymaster : ", execApprove);

  const userOp1 = await scw1.createUnsignedUserOp({
    target: testToken.address,
    data: tokenApprovePaymaster,
  });

  userOp1.callData = execApprove;
  userOp1.preVerificationGas = 1000000;
  userOp1.paymasterAndData = ethers.utils.hexConcat([
    paymasterContract.address,
    testToken.address,
    ]);

  console.log("userOp1 : ", userOp1);

  const client = new HttpRpcClient(
    "http://localhost:3000/rpc",
    "0x7aD823A5cA21768a3D3041118Bc6e981B0e4D5ee",
    31337
  );

  const signedUserOp1 = await scw1.signUserOp(userOp1);

  console.log(await client.sendUserOpToBundler(signedUserOp1));
  console.log("ERC20 Balance before userOp : ", (await testToken.balanceOf(await scw1.getAccountAddress())).toString());
  // console.log("Native Balance before userOp : ",(await provider.getBalance(await scw1.getAccountAddress())).toString());
  // console.log("Paymaster Native Balance before userOp : ",(await provider.getBalance(paymasterContract.address)).toString());
}

main();
