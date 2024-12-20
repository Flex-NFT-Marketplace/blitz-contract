const {
  Account,
  hash,
  Contract,
  json,
  Calldata,
  CallData,
  RpcProvider,
  shortString,
  eth,
  uint256,
} = require("starknet");
const fs = require("fs");

const RPC = "https://starknet-sepolia.public.blastapi.io/rpc/v0_7";
const provider = new RpcProvider({ nodeUrl: RPC });

const PRIVATE_KEY = "";
const ACCOUNT_ADDRESS =
  "0x05dcb49a8217eab5ed23e4a26df044edaf1428a5c7b30fa2324fa39a28288f6b";

const account = new Account(provider, ACCOUNT_ADDRESS, PRIVATE_KEY);

async function deployContract() {
  console.log("🚀 Deploying with Account: " + account.address);
  const compiledContractCasm = json.parse(
    fs
      .readFileSync(
        "/home/hayden/workplace/atemu/atemu-contract/target/dev/atemu_MyNFT.compiled_contract_class.json"
      )
      .toString("ascii")
  );
  const compiledContractSierra = json.parse(
    fs
      .readFileSync(
        "/home/hayden/workplace/atemu/atemu-contract/target/dev/atemu_MyNFT.contract_class.json"
      )
      .toString("ascii")
  );

  const stringToByteArray = (str) => ({
    len: str.length,
    data: str.split("").map((char) => char.charCodeAt(0)),
  });

  const contractCallData = new CallData(compiledContractSierra.abi);

  const contractConstructor = contractCallData.compile("constructor", {
    recipient:
      "0x05dcb49a8217eab5ed23e4a26df044edaf1428a5c7b30fa2324fa39a28288f6b",
  });

  console.log(contractConstructor);

  const deployContractResponse = await account.declareAndDeploy({
    contract: compiledContractSierra,
    casm: compiledContractCasm,
    constructorCalldata: contractConstructor,
  });

  console.log(
    "MyNFT Contract Class Hash =",
    deployContractResponse.declare.class_hash
  );
  console.log(
    "✅ MyNFT Contract Deployed: ",
    deployContractResponse.deploy.contract_address
  );
} //0x42b7a05fbd3a8bab52ae25a814813da7f5937584cf3e3fa248e69701188cf1d

deployContract();

/*
MyNFT Contract Class Hash = 0xe6516618aeee97b0b052f4389bc4a7e7fe1bbcf2959a6e4473801c03d17f74
✅ MyNFT Contract Deployed:  0x15eb6f7f5cfc975ce0eba18156dfa88c2b81c343ba808a62507da42a09f821f
  */
