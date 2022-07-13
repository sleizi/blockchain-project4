const FlightSuretyApp = artifacts.require("FlightSuretyApp");
const FlightSuretyData = artifacts.require("FlightSuretyData");
const fs = require('fs');
const path = require('path');

module.exports = async function (deployer) {

    let firstAirline = '0xf17f52151EbEF6C7334FAD080c5704D77216b732';
    await deployer.deploy(FlightSuretyData)
    await deployer.deploy(FlightSuretyApp, FlightSuretyData.address)
    let config = {
        localhost: {
            url: 'http://localhost:8545',
            dataAddress: FlightSuretyData.address,
            appAddress: FlightSuretyApp.address
        }
    }
    fs.writeFileSync(path.resolve(__dirname, '../src/dapp/config.json'), JSON.stringify(config, null, '\t'), 'utf-8');
    fs.writeFileSync(path.resolve(__dirname, '../src/server/config.json'), JSON.stringify(config, null, '\t'), 'utf-8');
}
