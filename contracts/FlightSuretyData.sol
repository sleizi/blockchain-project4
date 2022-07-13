pragma solidity ^0.4.25;

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

contract FlightSuretyData {
    using SafeMath for uint256;

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    uint256 private MULTIPARTY_CONSENSUS = 4;

    address private contractOwner; // Account used to deploy contract
    bool private operational = true; // Blocks all state changes throughout the contract if false

    struct Airline {
        bool isRegistered;
        bool isFunded;
        uint256 fundingAmount;
        uint256 votes;
    }

    mapping(address => Airline) private airlines;
    uint256 private airlinesCount = 1;

    address[] private passengers;
    mapping(address => bool) private isPassenger;
    mapping(address => mapping(bytes32 => uint256))
        private passengerFlightInsurances;
    mapping(address => uint256) private passengerBalances;

    mapping(address => bool) private authorizedCallers;

    uint256 public constant AIRLINE_REGISTRATION_FEE = 10 ether;

    uint256 public constant MAX_INSURANCE_AMOUNT = 1 ether;

    /********************************************************************************************/
    /*                                       EVENT DEFINITIONS                                  */
    /********************************************************************************************/

    /**
     * @dev Constructor
     *      The deploying account becomes contractOwner
     */
    constructor() public {
        contractOwner = msg.sender;
        airlines[msg.sender] = Airline({
            isRegistered: true,
            isFunded: true,
            fundingAmount: AIRLINE_REGISTRATION_FEE,
            votes: 0
        });
    }

    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    // Modifiers help avoid duplication of code. They are typically used to validate something
    // before a function is allowed to be executed.

    /**
     * @dev Modifier that requires the "operational" boolean variable to be "true"
     *      This is used on all state changing functions to pause the contract in
     *      the event there is an issue that needs to be fixed
     */
    modifier requireIsOperational() {
        require(operational, "Contract is currently not operational");
        _; // All modifiers require an "_" which indicates where the function body will be added
    }

    /**
     * @dev Modifier that requires the "ContractOwner" account to be the function caller
     */
    modifier requireContractOwner() {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    /**
     * @dev Modifier that requires the given sender to be a registered airline.
     */
    modifier requireCallerIsRegisteredAirline() {
        require(
            airlines[tx.origin].isRegistered,
            "You are not authorized to perform this operation"
        );
        _;
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    /**
     * @dev Get operating status of contract
     *
     * @return A bool that is the current operating status
     */
    function isOperational() external view returns (bool) {
        return operational;
    }

    /**
     * @dev Sets contract operations on/off
     *
     * When operational mode is disabled, all write transactions except for this one will fail
     */
    function setOperatingStatus(bool mode) external requireContractOwner {
        operational = mode;
    }

    function authorizeCaller(address contractAddress)
        external
        requireIsOperational
        requireContractOwner
    {
        authorizedCallers[contractAddress] = true;
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

    function isAirline(address airlineAddress) public view returns (bool) {
        return airlines[airlineAddress].isRegistered;
    }

    function setMultipartyConsensus(uint256 number)
        external
        requireIsOperational
        requireContractOwner
    {
        MULTIPARTY_CONSENSUS = number;
    }

    /**
     * @dev Add an airline to the registration queue
     *      Can only be called from FlightSuretyApp contract
     *
     */
    function registerAirline(address airlineAddress)
        external
        requireIsOperational
        requireCallerIsRegisteredAirline
        returns (bool success, uint256 votes)
    {
        require(
            airlines[tx.origin].isFunded,
            "You need to fund at least 10 ETH to participate before performing this operation"
        );
        require(
            !airlines[airlineAddress].isRegistered,
            "Airline has been registered"
        );

        if (airlinesCount < MULTIPARTY_CONSENSUS) {
            airlines[airlineAddress] = Airline(true, false, 0, 0);
            airlinesCount = airlinesCount.add(1);
            return (true, 0);
        }

        airlines[airlineAddress].votes = airlines[airlineAddress].votes.add(1);
        if (airlines[airlineAddress].votes.mul(2) >= airlinesCount) {
            airlines[airlineAddress].isRegistered = true;
            airlinesCount = airlinesCount.add(1);
            return (true, airlines[airlineAddress].votes);
        }

        return (false, airlines[airlineAddress].votes);
    }

    /**
     * @dev Buy insurance for a flight
     *
     */
    function buy(
        address airline,
        string flight,
        uint256 timestamp
    ) external payable requireIsOperational {
        require(
            !airlines[msg.sender].isRegistered,
            "An airline can not purchase insurance"
        );

        if (!isPassenger[msg.sender]) {
            isPassenger[msg.sender] = true;
            passengers.push(msg.sender);
        }

        bytes32 flightKey = getFlightKey(airline, flight, timestamp);
        uint256 totalAmount = passengerFlightInsurances[msg.sender][flightKey]
            .add(msg.value);
        require(
            totalAmount <= MAX_INSURANCE_AMOUNT,
            "You can not purchase flight insurance for more than 1 ether"
        );

        passengerFlightInsurances[msg.sender][
            flightKey
        ] = passengerFlightInsurances[msg.sender][flightKey].add(msg.value);
    }

    /**
     *  @dev Credits payouts to insurees
     */
    function creditInsurees(
        address airline,
        string flight,
        uint256 timestamp
    ) external requireIsOperational requireContractOwner {
        bytes32 flightKey = getFlightKey(airline, flight, timestamp);
        for (uint256 i = 0; i < passengers.length; i++) {
            address passenger = passengers[i];
            uint256 payout = passengerFlightInsurances[passenger][flightKey];
            if (payout > 0) {
                passengerFlightInsurances[passenger][flightKey] = 0;
                passengerBalances[passenger] = passengerBalances[passenger].add(
                    payout
                );
            }
        }
    }

    /**
     *  @dev Transfers eligible payout funds to insuree
     *
     */
    function pay() external {
        require(
            passengerBalances[msg.sender] > 0,
            "You have no balance to withdraw"
        );
        uint256 balance = passengerBalances[msg.sender];
        passengerBalances[msg.sender] = 0;
        msg.sender.transfer(balance);
    }

    /**
     * @dev Initial funding for the insurance. Unless there are too many delayed flights
     *      resulting in insurance payouts, the contract should be self-sustaining
     *
     */
    function fund() public payable requireCallerIsRegisteredAirline {
        airlines[msg.sender].fundingAmount = airlines[msg.sender]
            .fundingAmount
            .add(msg.value);
        if (airlines[msg.sender].fundingAmount >= AIRLINE_REGISTRATION_FEE) {
            airlines[msg.sender].isFunded = true;
        }
    }

    function getFlightKey(
        address airline,
        string flight,
        uint256 timestamp
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    function getAirlinesCount()
        external
        view
        requireCallerIsRegisteredAirline
        returns (uint256)
    {
        return airlinesCount;
    }

    /**
     * @dev Fallback function for funding smart contract.
     *
     */
    function() external payable {
        fund();
    }
}
