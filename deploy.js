
async function main() {
    // We get the contract to deploy
    const contract = await ethers.getContractFactory('StakingToken1');
    console.log('Deploying StakingToken...');
    const token = await contract.deploy('0x945d9AF572a89627B29aafa0E3B66e4f867E32a7');
    await token.deployed();
    console.log('StakingToken deployed to:', token.address);
    console.log(`Please enter this command below to verify your contract:`)
    console.log(`npx hardhat verify --network testnet ${token.address} 0x945d9AF572a89627B29aafa0E3B66e4f867E32a7`)
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });