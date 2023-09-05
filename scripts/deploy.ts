import { ethers } from "ethers";
import { ContractFactory } from "ethers";
import PaymasterArtifact from "../artifacts/contracts/CustomPaymaster.sol/CustomPaymaster.json";
import ERC20PaymasterArtifact from "../artifacts/contracts/CustomERC20Paymaster.sol/CustomERC20Paymaster.json";
import TestTokenArtifact from "../artifacts/contracts/TestToken.sol/TestToken.json";

async function main() {
  const metadata = PaymasterArtifact.bytecode;
  const abi = PaymasterArtifact.abi;

  const mnemonic =
    "test test test test test test test test test test test junk";
  const pvtkey1 = ethers.Wallet.fromMnemonic(
    mnemonic,
    "m/44'/60'/0'/0/0"
  ).privateKey;

  const provider = ethers.getDefaultProvider("http://127.0.0.1:8545");

  const signer = new ethers.Wallet(pvtkey1,provider);

  const customPaymasterContract = new ethers.ContractFactory(
    abi,
    metadata,
    signer
  );

  const customerc20paymasterContract = new ethers.ContractFactory(
    ERC20PaymasterArtifact.abi,
    ERC20PaymasterArtifact.bytecode,
    signer
  );

  const testTokenContract = new ethers.ContractFactory(
    TestTokenArtifact.abi,
    TestTokenArtifact.bytecode,
    signer
  );

  const custompaymaster = await customPaymasterContract.deploy(
    "0x3647fABd9F0a8CF5CCd9246Cd559BB2E40a8c43F",
    "USDC",
    "0x7aD823A5cA21768a3D3041118Bc6e981B0e4D5ee",
  );

  const customerc20paymaster = await customerc20paymasterContract.deploy(
    "0x7aD823A5cA21768a3D3041118Bc6e981B0e4D5ee",
  );

  const token1 = await testTokenContract.deploy("TestToken1", "TT1");

  console.log(`CustomPaymaster deployed to ${custompaymaster.address}`);
  console.log(`CustomERC20Paymaster deployed to ${customerc20paymaster.address}`);
  console.log(`TestToken1 deployed to ${token1.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
