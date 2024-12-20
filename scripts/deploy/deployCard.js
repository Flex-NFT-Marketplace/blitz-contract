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
        "/home/hayden/workplace/atemu/atemu-contract/target/dev/atemu_Cards.compiled_contract_class.json"
      )
      .toString("ascii")
  );
  const compiledContractSierra = json.parse(
    fs
      .readFileSync(
        "/home/hayden/workplace/atemu/atemu-contract/target/dev/atemu_Cards.contract_class.json"
      )
      .toString("ascii")
  );

  const stringToByteArray = (str) => ({
    len: str.length,
    data: str.split("").map((char) => char.charCodeAt(0)),
  });

  const contractCallData = new CallData(compiledContractSierra.abi);

  const contractConstructor = contractCallData.compile("constructor", {
    owner: "0x05dcb49a8217eab5ed23e4a26df044edaf1428a5c7b30fa2324fa39a28288f6b",
    base_uri: "https://exampleBaseURI/",
  });

  console.log(contractConstructor);

  const deployContractResponse = await account.declareAndDeploy({
    contract: compiledContractSierra,
    casm: compiledContractCasm,
    constructorCalldata: contractConstructor,
  });

  console.log(
    "Test Contract Class Hash =",
    deployContractResponse.declare.class_hash
  );
  console.log(
    "✅ NFT Contract Deployed: ",
    deployContractResponse.deploy.contract_address
  );
} //0x42b7a05fbd3a8bab52ae25a814813da7f5937584cf3e3fa248e69701188cf1d

deployContract();

/*
Test Contract Class Hash = 0x1fe60d676ba14393550ee447ede7181b7d1f0b34b898707fb1d14cfe4f462ca
✅ NFT Contract Deployed:  0x164c6ae8663dc3e07a3c4971425463d6212144d6fa68e0732020982d630368c
*/
