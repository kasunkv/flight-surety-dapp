const truffleAssert = require('truffle-assertions');
const truffleEvent  = require('truffle-events');
const sha3 = require('js-sha3').keccak_256

const FlightSuretyApp = artifacts.require("FlightSuretyApp");
const FlightSuretyData = artifacts.require("FlightSuretyData");

//var Test = require('../config/testjs');
var BigNumber = require('bignumber.js');
const truffleAssertions = require('truffle-assertions');


contract('Flight Surety', async (accounts) => {
	let flightSuretyApp;
	let flightSuretyData;
	const owner = accounts[0];
	const firstAirline = owner;

  before(async () => {
    //config = await Test.Config(accounts);
    //await flightSuretyData.authorizeCaller(flightSuretyApp.address);

		flightSuretyApp = await FlightSuretyApp.deployed();
		flightSuretyData = await FlightSuretyData.deployed();

		await flightSuretyData.auhorizeCaller(flightSuretyApp.address);
  });

  /****************************************************************************************/
  /* Operations and Settings                                                              */
  /****************************************************************************************/

  it('[multiparty] Has correct initial isOperational() value', async function () {
    // Get operating status
    let status = await flightSuretyData.isOperational.call();
    assert.equal(status, true, 'Incorrect initial operating status value');
  });

  it('[multiparty] Can block access to setOperationalStatus() for non-Contract Owner account', async function () {
    // Ensure that access is denied for non-Contract Owner account
    let accessDenied = false;
		let tx;
    try {
      tx = await flightSuretyData.setOperationalStatus(false, { from: accounts[2] });
    } catch (err) {
      accessDenied = true;
    }
    assert.equal(accessDenied, true, 'Access not restricted to Contract Owner');
  });

  it('[multiparty] Can allow access to setOperationalStatus() for Contract Owner account', async function () {
    // Ensure that access is allowed for Contract Owner account
    let accessDenied = false;
    try {
      await flightSuretyData.setOperationalStatus(false, { from: owner });
    } catch (err) {
      accessDenied = true;
    }
    assert.equal(accessDenied, false, 'Access not restricted to Contract Owner');

		// Set it back for other tests to work
    await flightSuretyData.setOperationalStatus(true, { from: owner });
  });

  it('[multiparty] Can block access to functions using whenNotPaused when operating status is false', async function () {
    await flightSuretyData.setOperationalStatus(false, { from: owner });

    let reverted = false;
    try {
			const funds = web3.utils.toWei('1', 'ether');
      await flightSuretyData.fund({ from: owner, value: funds});
    } catch (err) {
      reverted = true;
    }
    assert.equal(reverted, true, 'Access not blocked for fund');

    // Set it back for other tests to work
    await flightSuretyData.setOperationalStatus(true, { from: owner });
  });

  it('[airline] Registered airline with registerAirline() is not funded until funds are added.', async () => {
    // ARRANGE
    let newAirline = accounts[1];

    // ACT
    try {
      await flightSuretyApp.registerAirline(newAirline, "Second Airline", { from: firstAirline });
    } catch (err) {
			console.error(err);
		}
    let result = await flightSuretyData.isFundedAirline.call(newAirline);

    // ASSERT
    assert.equal(result, false, "Airline should not be able to register another airline if it hasn't provided funding");
  });

  it('[airline] Can not be funded with less then 10 ether', async () => {
    const fee = web3.utils.toWei('9', 'ether');
		const airlineAddr = accounts[1];

    try {
      await flightSuretyApp.fundAirline({ from: airlineAddr, value: fee });
    } catch (err) {
			console.error(err);
		}

		let result = await flightSuretyData.isFundedAirline.call(airlineAddr);
    assert.equal(result, false);
  });

  it('[airline] Can be funded with 10 or more ether only', async () => {
    const fee = web3.utils.toWei('10', 'ether');
		const airlineAddr = accounts[1];

    try {
      await flightSuretyApp.fundAirline({ from: airlineAddr, value: fee });
    } catch (err) {
      console.error(err);
    }
    let result = await flightSuretyData.isFundedAirline.call(airlineAddr);
    assert.equal(result, true, 'Airline should be funded');
  });

  it('[airline] Upto 4 airline can be registered without 50% consensus', async () => {
    try {
      await flightSuretyApp.registerAirline(accounts[2], 'Third Airline', { from: firstAirline });
      await flightSuretyApp.registerAirline(accounts[3], 'Fourth Airline', { from: firstAirline });
    } catch (err) {
      console.error(err);
    }
    const registrationResult3 = await flightSuretyData.isRegisteredAirline.call(accounts[2]);
    const registrationResult4 = await flightSuretyData.isRegisteredAirline.call(accounts[3]);
		const approvalResult3 = await flightSuretyData.isApprovedAirline.call(accounts[2]);
		const approvalResult4 = await flightSuretyData.isApprovedAirline.call(accounts[3]);

    assert.equal(registrationResult3, true, 'The Third Airline Registered Successfully.');
    assert.equal(registrationResult4, true, 'The Fourth Airline Registered Successfully.');
		assert.equal(approvalResult3, true, 'The Third Airline should not be approved.');
    assert.equal(approvalResult4, true, 'The Fourth Airline should not be approved.');
  });

  it('[airline] Fifth airline waiting to be registered requires at least 50% consensus votes', async () => {
    try {
      await flightSuretyApp.registerAirline(accounts[4], 'Fifth Airline', { from: firstAirline });
    } catch (err) {
      console.error(err);
    }

		const registrationResult = await flightSuretyData.isRegisteredAirline.call(accounts[4]);
    const approvalResult = await flightSuretyData.isApprovedAirline.call(accounts[4]);

		assert.equal(registrationResult, true, 'Fifth airline should be registered.');
		assert.equal(approvalResult, false, 'Fifth airline should not be approved.');
  });

  it('[insurance] Passenger purchase insurance paying 1 ether max', async () => {
    const insuranceAmount = web3.utils.toWei('0.8', 'ether');
    const flightName = 'First Airline';
    const firstAirlineAddr = accounts[0];
    const timeStamp = 1630021956;
    const passengerAddress = accounts[15];
		const airlineFund = web3.utils.toWei('10', 'ether');
    let error;

    try {
			await flightSuretyApp.fundAirline({from: accounts[0], value: airlineFund});
			await flightSuretyApp.buyInsurancePolicy(firstAirlineAddr, flightName, timeStamp, { from: passengerAddress, value: insuranceAmount });
			error = false;
    } catch (err) {
      error = true;
			console.error(err);
    }

		assert.equal(error, false, 'Purchase did not complete successfully.');
  });
});
