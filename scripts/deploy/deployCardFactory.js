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

// StarkNet RPC provider (can be changed to match your preferred RPC provider)
const RPC = "https://starknet-sepolia.public.blastapi.io/rpc/v0_7";
const provider = new RpcProvider({ nodeUrl: RPC });

// Private key and account address for the deployer account
const PRIVATE_KEY = "";
const ACCOUNT_ADDRESS =
  "0x05dcb49a8217eab5ed23e4a26df044edaf1428a5c7b30fa2324fa39a28288f6b";

const account = new Account(provider, ACCOUNT_ADDRESS, PRIVATE_KEY);

// Helper function to convert a string to a byte array
const stringToByteArray = (str) => ({
  len: str.length,
  data: str.split("").map((char) => char.charCodeAt(0)),
});

async function deployContract() {
  try {
    console.log("🚀 Deploying with Account: " + account.address);

    // Read and parse the compiled contracts (CASM and Sierra)
    const compiledContractCasm = json.parse(
      fs
        .readFileSync(
          "/home/hayden/workplace/atemu/atemu-contract/target/dev/atemu_CardFactory.compiled_contract_class.json"
        )
        .toString("ascii")
    );
    const compiledContractSierra = json.parse(
      fs
        .readFileSync(
          "/home/hayden/workplace/atemu/atemu-contract/target/dev/atemu_CardFactory.contract_class.json"
        )
        .toString("ascii")
    );

    // The constructor calldata, this will be specific to your CardFactory contract
    // Update the addresses and inputs according to your needs
    const contractCallData = new CallData(compiledContractSierra.abi);

    const constructorCalldata = contractCallData.compile("constructor", {
      owner:
        "0x05dcb49a8217eab5ed23e4a26df044edaf1428a5c7b30fa2324fa39a28288f6b",
      card_collectible_class:
        "0x1fe60d676ba14393550ee447ede7181b7d1f0b34b898707fb1d14cfe4f462ca", // Replace this with the actual class hash of the CardCollectible
      randomness_contract_address:
        "0x60c69136b39319547a4df303b6b3a26fab8b2d78de90b6bd215ce82e9cb515c", // Address for Sepolia (update for Mainnet if needed)
      eth_address:
        "0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7", // Address for the ETH token contract
    });

    console.log("📦 Constructor calldata: ", constructorCalldata);

    // Declare and deploy the contract
    const deployContractResponse = await account.declareAndDeploy({
      contract: compiledContractSierra,
      casm: compiledContractCasm,
      constructorCalldata: constructorCalldata,
    });

    console.log(
      "✅ Contract Class Hash = ",
      deployContractResponse.declare.class_hash
    );
    console.log(
      "🎉 Contract Deployed at Address = ",
      deployContractResponse.deploy.contract_address
    );
  } catch (error) {
    console.error("❌ Error deploying contract: ", error);
  }
}

deployContract();
