import { network } from "hardhat";

const { ethers } = await network.connect({ network: "testnet" });

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contract with the account:", deployer.address);

  // 1) Deploy the wrapper contract
  // The deployer will also be the owner of our NFT contract
  const SimpleHTS721 = await ethers.getContractFactory(
    "SimpleHTS721",
    deployer
  );
  const NAME = "SimpleHTS721NFTCollection";
  const SYMBOL = "SHTS721";
  const HBAR_TO_SEND = "15"; // HBAR to send with constructor
  console.log(
    `Calling constructor() with ${HBAR_TO_SEND} HBAR to create the HTS collection...`
  );
  const contract = await SimpleHTS721.deploy(NAME, SYMBOL, "", {
    value: ethers.parseEther(HBAR_TO_SEND)
  });
  await contract.waitForDeployment();

  // 2) Mint a token in the HTS collection
  const tx = await contract.mintTo(deployer.address);
  await tx.wait();
  console.log("mintTo() tx hash:", tx.hash);

  // 3) Read the created HTS token address
  const contractAddress = await contract.getAddress();
  console.log("SimpleHTS721 contract deployed at:", contractAddress);
  const tokenAddress = await contract.hederaTokenAddress();
  console.log(
    "Underlying HTS NFT Collection (ERC721 facade) address:",
    tokenAddress
  );
}

main().catch(console.error);
