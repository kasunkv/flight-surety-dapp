// SPDX-License-Identifier: MIT

pragma solidity >=0.8.10;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract FlightSuretyData is Ownable, Pausable, ReentrancyGuard {
  using SafeMath for uint256;

  struct Airline {
    string name;
    address wallet;
    bool isRegistered;
    bool isApproved;
    uint256 funds;
    uint256 votes;
  }

  struct Passenger {
    address wallet;
    uint256 credit;
    mapping(bytes32 => uint256) insuredFlights;
  }

  mapping(address => bool) private authorizedCallers;
  mapping(address => Airline) private airlines;
  mapping(address => Passenger) private passengers;
  mapping(address => bool) private passengerLookup;

  address[] public passengerAddresses = new address[](0);

  uint256 public approvedAirlinesCount = 0;

  uint256 public constant INSURANCE_COVER_PRICE_LIMIT = 1 ether;
  uint256 public constant MIN_AIRLINE_FUNDS = 10 ether;
  uint256 private constant MIN_AIRLINE_COUNT_FOR_CONCENSUS = 4;

  event CallerAuthorized(address indexed callerAddr);
  event CallerAuthorizationRevoved(address indexed callerAddr);
  event ApprovedAirline(address indexed airlineAddr);
  event VotedForAirline(address indexed airlineAddr);
  event RegisteredAirline(address indexed airlineAddr, string indexed airlineName);
  event InsuranceBought(address indexed passenger, bytes32 flightKey, uint256 policyValue);
  event InsurancePayoutCredited(address indexed passenger, bytes32 flightKey, uint256 payoutValue);
  event InsuranceClaimPaid(address indexed passenger, uint256 payoutValue);
  event AirlineFunded(address indexed airlineAddr, uint256 amount);

  constructor() {
    // Contract deployer as one of the authorized callers, also the contract owner with Ownable
    authorizedCallers[msg.sender] = true;

    // Register the deployer as the first airline. The first airline is considered automatically approved
    airlines[msg.sender] = Airline({name: "First Airline", wallet: msg.sender, isRegistered: true, isApproved: true, funds: 0, votes: 1});

    approvedAirlinesCount++;

    emit RegisteredAirline(msg.sender, "First Airline");
    emit ApprovedAirline(msg.sender);
  }


  /* #region Modifiers */

  modifier authorizedCaller() {
    require(authorizedCallers[tx.origin], "Caller is not authorized");
    _;
  }

  modifier validateAddress(address _addr) {
    require(_addr != address(0), "Not a valid address");
    _;
  }

  modifier registeredAirline(address _airlineAddr) {
    require(isAirlineRegistered(_airlineAddr), "The airline must be registered.");
    _;
  }

  modifier unregisteredAirline(address _airlineAddr) {
    require(!isAirlineRegistered(_airlineAddr), "The airline must be new and unregistered");
    _;
  }

  modifier fundedAirline(address _airlineAddr) {
    require(isAirlineFunded(_airlineAddr), "Can not buy an insurance from an unfunded airline");
    _;
  }

  modifier notContract() {
    require(msg.sender == tx.origin, "Contracts are not allowed");
    _;
  }

  modifier approvedAirline(address _caller) {
    require(isAirlineApproved(_caller), "Airline is not yet approved for voting");
    _;
  }

  /* #endregion */


  /* #region Internal functions */

  function isAirlineRegistered(address _airlineAddr) internal view returns (bool) {
    return airlines[_airlineAddr].isRegistered;
  }

  function isAirlineApproved(address _airlineAddr) internal view returns (bool) {
    return airlines[_airlineAddr].isApproved;
  }

  function isAirlineFunded(address _airlineAddr) internal view returns (bool) {
    return airlines[_airlineAddr].funds >= MIN_AIRLINE_FUNDS;
  }

  function getFlightKey(
    address airline,
    string memory flight,
    uint256 timestamp
  ) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(airline, flight, timestamp));
  }

  function _fund(address _airlineAddr) internal whenNotPaused registeredAirline(_airlineAddr) {
    require(msg.value > 0, "Not enough funds to add");
    airlines[_airlineAddr].funds += msg.value;

    emit AirlineFunded(_airlineAddr, msg.value);
  }

  /* #endregion */


  /* #region External functions */

  function isOperational() external view returns (bool) {
    return !paused();
  }

  function isRegisteredAirline(address _airlineAddr) external view returns (bool) {
    return isAirlineRegistered(_airlineAddr);
  }

  function isApprovedAirline(address _airlineAddr) external view returns (bool) {
    return isAirlineApproved(_airlineAddr);
  }

  function isFundedAirline(address _airlineAddr) external view returns (bool) {
    return isAirlineFunded(_airlineAddr);
  }

  function auhorizeCaller(address _callingAddr) external onlyOwner {
    authorizedCallers[_callingAddr] = true;

    emit CallerAuthorized(_callingAddr);
  }

  function revokeCallerAuthorization(address _callingAddr) external onlyOwner {
    authorizedCallers[_callingAddr] = false;

    emit CallerAuthorizationRevoved(_callingAddr);
  }

  function setOperationalStatus(bool _mode) external onlyOwner {
    if (_mode) {
      _unpause();
    } else {
      _pause();
    }
  }

  function registerAirline(address _origin, address _airlineAddr, string memory _airlineName) external
		whenNotPaused
		authorizedCaller
		validateAddress(_airlineAddr)
		unregisteredAirline(_airlineAddr)
		approvedAirline(_origin)
		returns (bool)
	{
		// Airline is not registered and less than X airlines are registered
    if (!isAirlineRegistered(_airlineAddr) && approvedAirlinesCount < MIN_AIRLINE_COUNT_FOR_CONCENSUS) {
      airlines[_airlineAddr] = Airline({
        name: _airlineName,
        wallet: _airlineAddr,
        isRegistered: true,
        isApproved: true,
        funds: 0,
        votes: 1 // If the airlines is newly added, Airline who registers the new airline is considered as voted for the new airline.
      });

      approvedAirlinesCount++;

      emit RegisteredAirline(_airlineAddr, _airlineName);
      emit VotedForAirline(_airlineAddr);

    }
		// Airline is not registered, but more than X number of airlines registered so consensus is needed. So approval is set to false.
		else if (!isAirlineRegistered(_airlineAddr)) {
			airlines[_airlineAddr] = Airline({
        name: _airlineName,
        wallet: _airlineAddr,
        isRegistered: true,
        isApproved: false,
        funds: 0,
        votes: 0
      });

			emit RegisteredAirline(_airlineAddr, _airlineName);
		}
		// Airline is registered, so go for voting.
		else {
      vote(_origin, _airlineAddr);
    }

    return true;
  }

  function vote(address _origin, address _airlineAddr) internal
    whenNotPaused
    registeredAirline(_airlineAddr) // Airline being voted must be registered
    approvedAirline(_origin) // The airline that is voting must be an approved airline.
  {
    // Vote for the airline
    airlines[_airlineAddr].votes++;
    emit VotedForAirline(_airlineAddr);

    // Check if the concensus criteria is met
    if (approvedAirlinesCount < MIN_AIRLINE_COUNT_FOR_CONCENSUS || airlines[_airlineAddr].votes >= approvedAirlinesCount.div(2)) {
      airlines[_airlineAddr].isApproved = true;
      approvedAirlinesCount++;

      emit ApprovedAirline(_airlineAddr);
    }
  }

  function buy(
    address _airline,
    string memory _flight,
    uint256 _timestamp
  ) external payable whenNotPaused {
    require(msg.value > 0, "Payment required to buy an insurance");

    bytes32 flightKey = getFlightKey(_airline, _flight, _timestamp);

    uint256 balance = 0;
    uint256 policyValue = 0;

    if (msg.value > INSURANCE_COVER_PRICE_LIMIT) {
      balance = msg.value.sub(INSURANCE_COVER_PRICE_LIMIT);
      policyValue = INSURANCE_COVER_PRICE_LIMIT;
    } else {
      policyValue = msg.value;
    }

    if (!passengerLookup[msg.sender]) {
      passengerLookup[msg.sender] = true;
      passengerAddresses.push(msg.sender);
    }

    if (passengers[msg.sender].wallet != msg.sender) {
      passengers[msg.sender].wallet = msg.sender;
      passengers[msg.sender].credit = 0;
      passengers[msg.sender].insuredFlights[flightKey] = policyValue;
    } else {
      passengers[msg.sender].insuredFlights[flightKey] = policyValue;
    }

    if (balance > 0) {
      payable(msg.sender).transfer(balance);
    }

    emit InsuranceBought(msg.sender, flightKey, policyValue);
  }

  function creditInsurees(
    address _airline,
    string memory _flight,
    uint256 _timestamp
  ) external whenNotPaused {
    bytes32 flightKey = getFlightKey(_airline, _flight, _timestamp);

    for (uint256 i = 0; i < passengerAddresses.length; i++) {
      address passengerAddr = passengerAddresses[i];

      if (passengers[passengerAddr].insuredFlights[flightKey] != 0) {
        uint256 insuredAmount = passengers[passengerAddr].insuredFlights[flightKey];
        uint256 insuranceClaim = insuredAmount + insuredAmount.div(2);

        passengers[passengerAddr].insuredFlights[flightKey] = 0;
        passengers[passengerAddr].credit += insuranceClaim;

        emit InsurancePayoutCredited(passengerAddr, flightKey, insuranceClaim);
      }
    }
  }

  function pay(address _passenger) external whenNotPaused nonReentrant {
    require(passengers[_passenger].credit > 0, "Not enough credit to withdraw");
    uint256 contractBalance = address(this).balance;
    uint256 passengerCredit = passengers[_passenger].credit;

    require(contractBalance > passengerCredit, "Not enough funds to pay the insurance");

    passengers[_passenger].credit = 0;
    payable(_passenger).transfer(passengerCredit);

    emit InsuranceClaimPaid(_passenger, passengerCredit);
  }

  function fund(address _airlineAddr) external payable {
    _fund(_airlineAddr);
  }

	function getPassengerEntitlement(address _passengerAddr) external view returns (uint) {
		return passengers[_passengerAddr].credit;
	}

  fallback() external payable {

  }

  receive() external payable {
    // custom function code
  }

  /* #endregion */


	function getAirline(address _airline) external view returns (string memory name, address wallet, bool isRegistered, bool isApproved, uint256 funds, uint256 votes) {
		Airline memory air = airlines[_airline];

		name = air.name;
		wallet = air.wallet;
		isRegistered = air.isRegistered;
		isApproved = air.isApproved;
		funds = air.funds;
		votes = air.votes;
	}
}
