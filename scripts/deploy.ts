import { ethers } from "ethers";
import { ContractFactory } from "ethers";
import PaymasterArtifact from "../artifacts/contracts/CustomPaymaster.sol/CustomPaymaster.json";

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

  const custompaymaster = await customPaymasterContract.deploy(
    "0x3647fABd9F0a8CF5CCd9246Cd559BB2E40a8c43F",
    "USDC",
    "0x7aD823A5cA21768a3D3041118Bc6e981B0e4D5ee",
  );

  console.log(`CustomPaymaster deployed to ${custompaymaster.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
