// SPDX-License-Identifier: MIT

pragma solidity >=0.8.10;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

import "./IFlightSuretyData.sol";

contract FlightSuretyApp is Ownable, Pausable {
  using SafeMath for uint256;

  // Flight status codees
  uint8 private constant STATUS_CODE_UNKNOWN = 0;
  uint8 private constant STATUS_CODE_ON_TIME = 10;
  uint8 private constant STATUS_CODE_LATE_AIRLINE = 20;
  uint8 private constant STATUS_CODE_LATE_WEATHER = 30;
  uint8 private constant STATUS_CODE_LATE_TECHNICAL = 40;
  uint8 private constant STATUS_CODE_LATE_OTHER = 50;

  struct Flight {
    bool isRegistered;
    uint8 statusCode;
    uint256 updatedTimestamp;
    address airline;
  }

  mapping(bytes32 => Flight) private flights;
  mapping(address => address[]) private airlineVoters;

  IFlightSuretyData flightSuretyData;


  /* #region Modifiers */

  modifier requireOperationalDataContract() {
    require(flightSuretyData.isOperational(), "Fight surety data contract is not operational");
    _;
  }

  modifier validateAddress(address _addr) {
    require(_addr != address(0), "Not a valid address");
    _;
  }

  /* #endregion */


  constructor(address _dataContract) {
    flightSuretyData = IFlightSuretyData(_dataContract);
  }

  /* #region Public Methods */

  function isOperational() public view returns (bool) {
    return !paused();
  }

	function isApprovedAir(address _airline) public view returns (bool) {
    return flightSuretyData.isApprovedAirline(_airline);
  }

  function getAirline(address _airline)
    public
    returns (
      string memory name,
      address wallet,
      bool isRegistered,
      bool isApproved,
      uint256 funds,
      uint256 votes
    )
  {
    return flightSuretyData.getAirline(_airline);
  }

  /* #endregion */


  /* #region External Methods */

  function setDataContract(address _dataContract) external onlyOwner {
    flightSuretyData = IFlightSuretyData(_dataContract);
  }

  function registerAirline(address _airlineAddr, string memory _name) external whenNotPaused requireOperationalDataContract returns (bool success, uint256 votes) {
    success = flightSuretyData.registerAirline(msg.sender, _airlineAddr, _name);

    if (success) {
      airlineVoters[_airlineAddr].push(msg.sender);
    }

    return (success, airlineVoters[_airlineAddr].length);
  }

  function registerFlight(string memory name, uint256 timestamp) external view whenNotPaused requireOperationalDataContract {}

  // Generate a request for oracles to fetch flight information
  function fetchFlightStatus(
    address _airline,
    string memory _flight,
    uint256 _timestamp
  ) external whenNotPaused {
    uint8 index = getRandomIndex(msg.sender);

    // Generate a unique key for storing the request
    bytes32 key = keccak256(abi.encodePacked(index, _airline, _flight, _timestamp));
    ResponseInfo storage info = oracleResponses[key];
    info.requester = msg.sender;
    info.isOpen = true;

    emit OracleRequest(index, _airline, _flight, _timestamp);
  }

  function buyInsurancePolicy(
    address _airline,
    string memory _flight,
    uint256 _timestamp
  ) external payable whenNotPaused requireOperationalDataContract {
    flightSuretyData.buy{value: msg.value}(_airline, _flight, _timestamp);
  }

  function withdrawIsuranceClaim(address _passengerAddr) external whenNotPaused requireOperationalDataContract validateAddress(_passengerAddr) {
    flightSuretyData.pay(_passengerAddr);
  }

  function fundAirline() external payable whenNotPaused requireOperationalDataContract {
    flightSuretyData.fund{value: msg.value}(msg.sender);
  }

	function isAirlineRegistered(address _airlineAddr) external view returns (bool) {
    return flightSuretyData.isRegisteredAirline(_airlineAddr);
  }

  function isAirlineApproved(address _airlineAddr) external view returns (bool) {
    return flightSuretyData.isApprovedAirline(_airlineAddr);
  }

  function isAirlineFunded(address _airlineAddr) external view returns (bool) {
    return flightSuretyData.isFundedAirline(_airlineAddr);
  }

	function getPassengerEntitlement(address _passengerAddr) external returns (uint) {
		return flightSuretyData.getPassengerEntitlement(_passengerAddr);
	}

  /* #endregion */

  function processFlightStatus(
    address _airline,
    string memory _flight,
    uint256 _timestamp,
    uint8 _statusCode
  ) internal whenNotPaused requireOperationalDataContract {
    if (_statusCode == STATUS_CODE_LATE_AIRLINE) {
      flightSuretyData.creditInsurees(_airline, _flight, _timestamp);
    }
  }


  /* #region Oracle Code */

  // Incremented to add pseudo-randomness at various points
  uint8 private nonce = 0;

  // Fee to be paid when registering oracle
  uint256 public constant REGISTRATION_FEE = 1 ether;

  // Number of oracles that must respond for valid status
  uint256 private constant MIN_RESPONSES = 3;

  struct Oracle {
    bool isRegistered;
    uint8[3] indexes;
  }

  // Track all registered oracles
  mapping(address => Oracle) private oracles;

  // Model for responses from oracles
  struct ResponseInfo {
    address requester; // Account that requested status
    bool isOpen; // If open, oracle responses are accepted
    mapping(uint8 => address[]) responses; // Mapping key is the status code reported
    // This lets us group responses and identify
    // the response that majority of the oracles
  }

  // Track all oracle responses
  // Key = hash(index, flight, timestamp)
  mapping(bytes32 => ResponseInfo) private oracleResponses;

  // Event fired each time an oracle submits a response
  event FlightStatusInfo(address airline, string flight, uint256 timestamp, uint8 status);

  event OracleReport(address airline, string flight, uint256 timestamp, uint8 status);

  // Event fired when flight status request is submitted
  // Oracles track this and if they have a matching index
  // they fetch data and submit a response
  event OracleRequest(uint8 index, address airline, string flight, uint256 timestamp);

  function oracleRegistrationFee() external pure returns (uint256) {
    return REGISTRATION_FEE;
  }

  // Register an oracle with the contract
  function registerOracle() external payable {
    // Require registration fee
    require(msg.value >= REGISTRATION_FEE, "Registration fee is required");

    uint8[3] memory indexes = generateIndexes(msg.sender);

    oracles[msg.sender] = Oracle({isRegistered: true, indexes: indexes});
  }

  function getMyIndexes() external view returns (uint8[3] memory) {
    require(oracles[msg.sender].isRegistered, "Not registered as an oracle");

    return oracles[msg.sender].indexes;
  }

  // Called by oracle when a response is available to an outstanding request
  // For the response to be accepted, there must be a pending request that is open
  // and matches one of the three Indexes randomly assigned to the oracle at the
  // time of registration (i.e. uninvited oracles are not welcome)
  function submitOracleResponse(
    uint8 index,
    address airline,
    string memory flight,
    uint256 timestamp,
    uint8 statusCode
  ) external {
    require((oracles[msg.sender].indexes[0] == index) || (oracles[msg.sender].indexes[1] == index) || (oracles[msg.sender].indexes[2] == index), "Index does not match oracle request");

    bytes32 key = keccak256(abi.encodePacked(index, airline, flight, timestamp));
    require(oracleResponses[key].isOpen, "Flight or timestamp do not match oracle request");

    oracleResponses[key].responses[statusCode].push(msg.sender);

    // Information isn't considered verified until at least MIN_RESPONSES
    // oracles respond with the *** same *** information
    emit OracleReport(airline, flight, timestamp, statusCode);
    if (oracleResponses[key].responses[statusCode].length >= MIN_RESPONSES) {
      emit FlightStatusInfo(airline, flight, timestamp, statusCode);

      // Handle flight status as appropriate
      processFlightStatus(airline, flight, timestamp, statusCode);
    }
  }

  function getFlightKey(
    address airline,
    string memory flight,
    uint256 timestamp
  ) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(airline, flight, timestamp));
  }

  // Returns array of three non-duplicating integers from 0-9
  function generateIndexes(address account) internal returns (uint8[3] memory) {
    uint8[3] memory indexes;
    indexes[0] = getRandomIndex(account);

    indexes[1] = indexes[0];
    while (indexes[1] == indexes[0]) {
      indexes[1] = getRandomIndex(account);
    }

    indexes[2] = indexes[1];
    while ((indexes[2] == indexes[0]) || (indexes[2] == indexes[1])) {
      indexes[2] = getRandomIndex(account);
    }

    return indexes;
  }

  // Returns array of three non-duplicating integers from 0-9
  function getRandomIndex(address account) internal returns (uint8) {
    uint8 maxValue = 10;

    // Pseudo random number...the incrementing nonce adds variation
    nonce++;
    uint8 random = uint8(uint256(keccak256(abi.encodePacked(block.timestamp, nonce, account))) % maxValue);

    if (nonce > 250) {
      nonce = 0; // Can only fetch blockhashes for last 256 blocks so we adapt
    }

    return random;
  }

  /* #endregion */

}
