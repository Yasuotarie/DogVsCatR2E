import { impersonateAccount } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers, network } from "hardhat";
const { MerkleTree } = require("merkletreejs");
import dogTraits from "./dogTraits.json";
import catTraits from "./catTraits.json";
const fs = require("fs");
import { NonceManager, Signer, getAddress } from "ethers";

const KIMBO_holder = "0xab32FA260b024b5db6bBe8D0983E9aC3fcd1a221";
const WAVAX_holder = "0xB65ceBF1371AB5e3748331004F652cd6C8f86aBe";
const KIMBO_adress = "0x184ff13B3EBCB25Be44e860163A5D8391Dd568c1";
const myaccount = "0xEb5a6a1323362668175920ABF8e4fA3b75c147FC";

async function main() {
  ////////////////////////////////////////////////////////////////////////////////////////////
  ////////////////////////START OF DEPLOYEMENT////////////////////////////////////////////////
  ////////////////////////////////////////////////////////////////////////////////////////////
  const tresor = "0x8626f6940e2eb28930efb4cef49b2d1f2c9c1199";

  const bscProvider = new ethers.JsonRpcProvider("http://127.0.0.1:8545/");

  const wallet = new ethers.Wallet(
    "0xdf57089febbacf7ba0bc227dafbffa9fc08a93fdc68e1e42411a14efcf23656e"
  );

  const signer: Signer = new NonceManager(wallet);
  const faucet = signer.connect(bscProvider);

  const token = await ethers.getContractFactory("TREATS");
  const tokendeploy = await token.connect(faucet).deploy(tresor);
  await tokendeploy.waitForDeployment();
  const tokenaddress = await tokendeploy.getAddress();
  console.log("tokenaddress", (await tokenaddress).toString());

  const traits = await ethers.getContractFactory("Traits");
  const traitsdeploy = await traits.connect(faucet).deploy();
  await traitsdeploy.waitForDeployment();
  const traitsaddress = await traitsdeploy.getAddress();
  console.log("traitsaddress", (await traitsaddress).toString());

  const dogvscat = await ethers.getContractFactory("DogVsCat");
  const dogvscatdeploy = await dogvscat.connect(faucet).deploy(tresor);
  await dogvscatdeploy.waitForDeployment();
  const dogvscataddress = await dogvscatdeploy.getAddress();
  console.log("dogvscataddress", (await dogvscataddress).toString());

  const barn = await ethers.getContractFactory("Barn");
  const barndeploy = await barn
    .connect(faucet)
    .deploy(dogvscataddress, traitsaddress, tresor);
  await barndeploy.waitForDeployment();
  const barnaddress = await barndeploy.getAddress();
  console.log("barnaddress", (await barnaddress).toString());

  const dogvscatmint = await ethers.getContractFactory("DogVsCatMint");
  const dogvscatmintdeploy = await dogvscatmint
    .connect(faucet)
    .deploy(dogvscataddress, tokenaddress, KIMBO_adress, tresor);
  await dogvscatmintdeploy.waitForDeployment();
  const dogvscatmintaddress = await dogvscatmintdeploy.getAddress();
  console.log("dogvscatmintaddress", (await dogvscatmintaddress).toString());

  ////////////////////////////////////////////////////////////////////////////////////////////
  ////////////////////////END OF DEPLOYEMENT//////////////////////////////////////////////////
  ////////////////////////////////////////////////////////////////////////////////////////////

  ////////////////////////////////////////////////////////////////////////////////////////////
  ////////////////////////START OF SETTINGS VALUES////////////////////////////////////////////
  ////////////////////////////////////////////////////////////////////////////////////////////
  await dogvscatdeploy.connect(faucet).setBarn(barnaddress);
  await dogvscatdeploy.connect(faucet).setTraits(traitsaddress);
  await traitsdeploy.connect(faucet).setNft(dogvscataddress);
  await traitsdeploy
    .connect(faucet)
    .setTraitCountForType(
      [0, 1, 2, 3, 4, 5, 6, 7, 8],
      [2, 2, 2, 2, 2, 2, 2, 2, 4]
    );
  await dogvscatmintdeploy.connect(faucet).unpause();
  await barndeploy.connect(faucet).setPaused(false);

  //Retrieve all the base64 code of all our design in the JSON (green background base64 etc.) each one stored in a list.
  const nbDesignTraits = Object.keys(dogTraits["Accessory"]).length;
  let AccessoryToUpload = [];
  let BackToUpload = [];
  let BodyToUpload = [];
  let HeadToUpload = [];
  let WeaponToUpload = [];
  let AccessoryToUploadcat = [];
  let BackToUploadcat = [];
  let BodyToUploadcat = [];
  let AlphaIndexToUpload = [];
  for (let j = 0; j < nbDesignTraits; j++) {
    let key = Object.keys(dogTraits["Accessory"][j]).toString();
    let value = Object.values(dogTraits["Accessory"][j]).toString();
    AccessoryToUpload.push({ name: key, png: value });
    key = Object.keys(dogTraits["Background"][j]).toString();
    value = Object.values(dogTraits["Background"][j]).toString();
    BackToUpload.push({ name: key, png: value });
    key = Object.keys(dogTraits["Body"][j]).toString();
    value = Object.values(dogTraits["Body"][j]).toString();
    BodyToUpload.push({ name: key, png: value });
    key = Object.keys(dogTraits["Head"][j]).toString();
    value = Object.values(dogTraits["Head"][j]).toString();
    HeadToUpload.push({ name: key, png: value });
    key = Object.keys(dogTraits["Weapon"][j]).toString();
    value = Object.values(dogTraits["Weapon"][j]).toString();
    WeaponToUpload.push({ name: key, png: value });
    key = Object.keys(catTraits["Accessory"][j]).toString();
    value = Object.values(catTraits["Accessory"][j]).toString();
    AccessoryToUploadcat.push({ name: key, png: value });
    key = Object.keys(catTraits["Background"][j]).toString();
    value = Object.values(catTraits["Background"][j]).toString();
    BackToUploadcat.push({ name: key, png: value });
    key = Object.keys(catTraits["Body"][j]).toString();
    value = Object.values(catTraits["Body"][j]).toString();
    BodyToUploadcat.push({ name: key, png: value });
  }

  for (let j = 0; j < 4; j++) {
    let key = Object.keys(catTraits["alphaIndex"][j]).toString();
    let value = Object.values(catTraits["alphaIndex"][j]).toString();
    AlphaIndexToUpload.push({ name: key, png: value });
  }

  //array to indicate the number of desgin in the trait with the order we can choose.
  let tableau = [0, 1];
  let tableauAlpha = [0, 1, 2, 3];

  //deploying all the traits.

  await traitsdeploy
    .connect(faucet)
    .uploadTraits(0, tableau, AccessoryToUpload);

  await traitsdeploy.connect(faucet).uploadTraits(1, tableau, BackToUpload);

  await traitsdeploy.connect(faucet).uploadTraits(2, tableau, BodyToUpload);

  await traitsdeploy.connect(faucet).uploadTraits(3, tableau, HeadToUpload);

  await traitsdeploy.connect(faucet).uploadTraits(4, tableau, WeaponToUpload);

  await traitsdeploy
    .connect(faucet)
    .uploadTraits(5, tableau, AccessoryToUploadcat);

  await traitsdeploy.connect(faucet).uploadTraits(6, tableau, BackToUploadcat);

  await traitsdeploy.connect(faucet).uploadTraits(7, tableau, BodyToUploadcat);

  await traitsdeploy
    .connect(faucet)
    .uploadTraits(8, tableauAlpha, AlphaIndexToUpload);

  //get the  value from traits
  // console.log(
  //   `valeur traits : ${await traitsdeploy.traitData(BigInt("1"), BigInt("1"))}`
  // );
  // console.log(
  //   `valeur traits : ${await traitsdeploy.traitData(BigInt("1"), BigInt("0"))}`
  // );

  ////////////////////////////////////////////////////////////////////////////////////////////
  ////////////////////////END OF SETTINGS VALUES//////////////////////////////////////////////
  ////////////////////////////////////////////////////////////////////////////////////////////
  //hash the controller role string for next
  const CONTROLLER_ROLE = ethers.keccak256(
    ethers.toUtf8Bytes("CONTROLLER_ROLE")
  );

  //grant role controller role to faucet signer to mint token (will be swapped in mainnet with the liquidity pool)

  await tokendeploy.connect(faucet).grantRole(CONTROLLER_ROLE, wallet.address);

  await tokendeploy.connect(faucet).mint(KIMBO_holder, BigInt("100000"));

  console.log(await tokendeploy.balanceOf(KIMBO_holder));

  //building the whiteliste
  const whiteList = [
    "0xab32FA260b024b5db6bBe8D0983E9aC3fcd1a221",
    "0x307Ae373a457F59E493886E48DEEBf20a245cFDB",
    "0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199",
  ];
  //whitelist for freemint
  const whiteListfree = [
    "0xab32FA260b024b5db6bBe8D0983E9aC3fcd1a221",
    "0xD5E3375E10d8854aD5386050B9F8716233d3cc8D",
    "0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199",
  ];

  //building the merkletree
  const leafNodes = whiteList.map((addr) => ethers.keccak256(addr));
  const merkleTree = new MerkleTree(leafNodes, ethers.keccak256, {
    sortPairs: true,
  });

  const leafNodesfree = whiteListfree.map((addr) => ethers.keccak256(addr));
  const merkleTreefree = new MerkleTree(leafNodesfree, ethers.keccak256, {
    sortPairs: true,
  });

  //root of the both withlist to be inserted in our smart contract
  const roothash = merkleTree.getRoot();
  const roothashfree = merkleTreefree.getRoot();

  //insert roof of merkle tree with owner of the contract : faucet

  await dogvscatmintdeploy
    .connect(faucet)
    .setMerkleRoot(roothashfree, roothash);

  //getting the proof of the kimbo holder adress : proof : To be sent when trying to mint when WL enabled.
  let hashedAddress = ethers.keccak256(wallet.address);
  let prooffree = merkleTreefree.getHexProof(hashedAddress);
  let proof = merkleTree.getHexProof(hashedAddress);

  let hashedAddress2 = ethers.keccak256(wallet.address);
  let prooffree2 = merkleTreefree.getHexProof(hashedAddress2);
  let proof2 = merkleTree.getHexProof(hashedAddress2);

  //getting KIMBO contract : already deployed contract

  //granting the controller role to dogvscatmint contract to be able to call function from the other : With the owner of the contract called.

  await dogvscatdeploy
    .connect(faucet)
    .grantRole(CONTROLLER_ROLE, dogvscatmintaddress);

  //freemint
  await dogvscatmintdeploy.connect(faucet).freemint(prooffree);
  //approve token to be transfered by dogvscatmint contract.

  //mint wiht kimbo : 1 NFT with the proof for WL. If no WL, dont need to send anythings.

  // await dogvscatmintdeploy.connect(faucet).mintWithKimbo(1, proof);

  // console.log(await dogvscatdeploy.ownerOf(0));
  // console.log(tx);
  console.log(await dogvscatdeploy.getAddress());
  console.log(await dogvscatdeploy.balanceOf(faucet));
  //   console.log(await traitsdeploy.traitCountForType(8));
  // let tx = await traitsdeploy.drawSVG(1);
  // console.log(tx);

  console.log("Your NFT counter : ", await dogvscatdeploy.balanceOf(faucet));

  await dogvscatmintdeploy
    .connect(faucet)
    .mintWithAvax(1, proof2, { value: ethers.parseEther("1") });

  await dogvscatmintdeploy.connect(faucet).simpleReveal([1]);
  console.log(await dogvscatdeploy.balanceOf(faucet));
}
main().then(() => console.info("done"));
