import { fillAndSign } from "./account-abstraction/test/UserOp";
import { HttpRpcClient, SimpleAccountAPI } from "@account-abstraction/sdk";
import { ethers } from "ethers";
import PaymasterArtifact from "../artifacts/contracts/CustomPaymaster.sol/CustomPaymaster.json";

async function main() {
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

  console.log("wallet1 address: ", wallet1.address);
  console.log("wallet2 address: ", wallet2.address);

  const paymasterABI = PaymasterArtifact.abi;
  const paymasterContract = new ethers.Contract(
    "0x21dF544947ba3E8b3c32561399E88B52Dc8b2823",
    paymasterABI,
    wallet1
  );

  //   await paymasterContract.deposit({
  //     value: ethers.utils.parseEther("10")
  //   })

  const scw1 = new SimpleAccountAPI({
    provider,
    entryPointAddress: "0x7aD823A5cA21768a3D3041118Bc6e981B0e4D5ee",
    owner: wallet1,
    factoryAddress: "0x3647fABd9F0a8CF5CCd9246Cd559BB2E40a8c43F",
  });

  const scw2 = new SimpleAccountAPI({
    provider,
    entryPointAddress: "0x7aD823A5cA21768a3D3041118Bc6e981B0e4D5ee",
    owner: wallet2,
    factoryAddress: "0x3647fABd9F0a8CF5CCd9246Cd559BB2E40a8c43F",
  });

  const scwAddress1 = await scw1.getAccountAddress();
  const scwAddress2 = await scw2.getAccountAddress();

  console.log("scw1 address: ", scwAddress1);
  console.log("scw2 address: ", scwAddress2);

  console.log(
    "Native Balance : ",
    await provider.getBalance(await wallet1.address)
  );
  console.log(
    "Native Balance : ",
    await provider.getBalance(await scw1.getAccountAddress())
  );
  console.log("Paymaster Token balance : ",
    (
      await paymasterContract.balanceOf(
        "0xc0B346d54091B5B527db14F5cc9F56a18E698E85"
      )
    ).toString()
  );

  // await paymasterContract
  //   .connect(wallet1)
  //   .mintTokens("0xc0B346d54091B5B527db14F5cc9F56a18E698E85", ethers.utils.parseEther("1000000000000000"))

  let userOp = await scw1.createUnsignedUserOp({
    target: wallet2.address,
    data: "0x",
  });

  userOp.preVerificationGas = 1000000;
  userOp.paymasterAndData = paymasterContract.address;

  let signedUserOp = await scw1.signUserOp(userOp);

  const client = new HttpRpcClient(
    "http://localhost:3000/rpc",
    "0x7aD823A5cA21768a3D3041118Bc6e981B0e4D5ee",
    31337
  );

  console.log(await client.sendUserOpToBundler(signedUserOp));

  console.log(
    "Native Balance : ",
    await provider.getBalance(await wallet1.address)
  );
  console.log(
    "Native Balance : ",
    await provider.getBalance(await scw1.getAccountAddress())
  );
  console.log("Paymaster Token balance : ",
    (
      await paymasterContract.balanceOf(
        "0xc0B346d54091B5B527db14F5cc9F56a18E698E85"
      )
    ).toString()
  );
}

main();
