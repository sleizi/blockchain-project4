
var Test = require('../config/testConfig.js');
var BigNumber = require('bignumber.js');
contract('Flight Surety Tests', async (accounts) => {

    var fund;
    var config;
    before('setup contract', async () => {

        config = await Test.Config(accounts);
        await config.flightSuretyData.authorizeCaller(config.flightSuretyApp.address);
        fund = new BigNumber(config.weiMultiple * 10);
    });

    /****************************************************************************************/
    /* Operations and Settings                                                              */
    /****************************************************************************************/

    it(`(multiparty) has correct initial isOperational() value`, async function () {

        // Get operating status
        let status = await config.flightSuretyData.isOperational.call();
        assert.equal(status, true, "Incorrect initial operating status value");
        var fund = config.weiMultiple
    });

    it(`(multiparty) can block access to setOperatingStatus() for non-Contract Owner account`, async function () {

        // Ensure that access is denied for non-Contract Owner account
        let accessDenied = false;
        try {
            await config.flightSuretyData.setOperatingStatus(false, { from: config.testAddresses[2] });
        }
        catch (e) {
            accessDenied = true;
        }
        assert.equal(accessDenied, true, "Access not restricted to Contract Owner");

    });

    it(`(multiparty) can allow access to setOperatingStatus() for Contract Owner account`, async function () {

        // Ensure that access is allowed for Contract Owner account
        let accessDenied = false;
        try {
            await config.flightSuretyData.setOperatingStatus(false);
        }
        catch (e) {
            accessDenied = true;
        }
        assert.equal(accessDenied, false, "Access not restricted to Contract Owner");

    });

    it(`(multiparty) can block access to functions using requireIsOperational when operating status is false`, async function () {

        await config.flightSuretyData.setOperatingStatus(false);

        let reverted = false;
        try {
            await config.flightSurety.setTestingMode(true);
        }
        catch (e) {
            reverted = true;
        }
        assert.equal(reverted, true, "Access not blocked for requireIsOperational");

        // Set it back for other tests to work
        await config.flightSuretyData.setOperatingStatus(true);

    });

    it('(airline) cannot register an Airline using registerAirline() if it is not funded', async () => {

        // ARRANGE
        let newAirline = accounts[2];

        // ACT
        try {
            await config.flightSuretyApp.registerAirline(newAirline, { from: config.firstAirline });
        }
        catch (e) {

        }
        let result = await config.flightSuretyData.isAirline.call(newAirline);

        // ASSERT
        assert.equal(result, false, "Airline should not be able to register another airline if it hasn't provided funding");

    });

    it('(airline) Only existing airline may register a new airline until there are at least four airlines registered', async () => {
        await config.flightSuretyApp.registerAirline(accounts[1], { from: config.owner });
        await config.flightSuretyApp.registerAirline(accounts[2], { from: config.owner });
        await config.flightSuretyApp.registerAirline(accounts[3], { from: config.owner });
        await config.flightSuretyApp.registerAirline(accounts[4], { from: config.owner });

        assert.equal(false, await config.flightSuretyData.isAirline(accounts[4]), "Requirement for multiparty consensus registration from 5th airline is not adapted");

    });

    it('(multiparty) Registration of fifth and subsequent airlines requires multi-party consensus of 50% of registered airlines', async () => {

        await config.flightSuretyData.fund({ value: fund, from: accounts[1] });

        await config.flightSuretyApp.registerAirline(accounts[5], { from: config.owner });

        // account[5] will not be registered because it is voted by only first airline
        assert.equal(false, await config.flightSuretyData.isAirline(accounts[5]), "Requirement for multiparty consensus registration from 5th airline is not adapted");

        await config.flightSuretyApp.registerAirline(accounts[5], { from: accounts[1] });

        // account[5] will be registered because it is voted by 2/4 participated airlines
        assert.equal(true, await config.flightSuretyData.isAirline(accounts[5]), "Requirement for multiparty consensus registration from 5th airline is not adapted");
    });

    it('(airline) Airline can be registered, but does not participate in contract until it submits funding of 10 ether (make sure it is not 10 wei)', async () => {
        await config.flightSuretyApp.registerAirline(accounts[6], { from: config.owner });
        await config.flightSuretyApp.registerAirline(accounts[6], { from: accounts[1] });
        try {
            await config.flightSuretyApp.registerAirline(accounts[6], { from: accounts[2] });
        }
        catch (e) {

        }
        // account[6] will not be registered (it is voted by only 2/5 participated airlines while account[2] did not submit funding
        assert.equal(false, await config.flightSuretyData.isAirline(accounts[6]));

        // account[2] submits funding
        await config.flightSuretyData.fund({ value: fund, from: accounts[2] });

        // Now account[2] can vote for account[6]
        await config.flightSuretyApp.registerAirline(accounts[6], { from: accounts[2] });

        // account[6] will be registered (it is voted by 3/5 participated airlines, include account[2]
        assert.equal(true, await config.flightSuretyData.isAirline(accounts[6]));
    });

});
