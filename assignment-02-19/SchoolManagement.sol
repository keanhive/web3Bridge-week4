// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title School Management System
/// @notice Manages student/staff registration, fee payments, and payroll using ERC20 tokens
contract SchoolToken is ERC20, Ownable {

    //  ENUMS & CONSTANTS
    enum Level { L100, L200, L300, L400 }

    enum PaymentStatus { PENDING, PAID }

    // School fee per level (in token units, 18 decimals)
    uint256 public constant FEE_L100 = 1000 * 10 ** 18;
    uint256 public constant FEE_L200 = 1500 * 10 ** 18;
    uint256 public constant FEE_L300 = 2000 * 10 ** 18;
    uint256 public constant FEE_L400 = 2500 * 10 ** 18;

    //  STRUCTS
    struct Student {
        uint256 id;
        string  name;
        address walletAddress;
        Level   level;
        PaymentStatus paymentStatus;
        uint256 feePaid;
        uint256 paymentTimestamp;
        bool    exists;
    }

    struct Staff {
        uint256 id;
        string  name;
        address walletAddress;
        string  role;
        uint256 salary;          // monthly salary in tokens
        uint256 lastPaidAt;      // timestamp of last salary payment
        bool    exists;
    }

    //  STATE
    uint256 private _studentIdCounter;
    uint256 private _staffIdCounter;

    // address → Student
    mapping(address => Student) private students;
    // address → Staff
    mapping(address => Staff)   private staffs;

    // keep ordered lists for iteration
    address[] private studentList;
    address[] private staffList;

    //  EVENTS
    event StudentRegistered(uint256 indexed id, address indexed student, string name, Level level);
    event FeePaid(address indexed student, uint256 amount, uint256 timestamp);
    event PaymentStatusUpdated(address indexed student, PaymentStatus status, uint256 timestamp);
    event StaffRegistered(uint256 indexed id, address indexed staff, string name, string role);
    event StaffPaid(address indexed staff, uint256 amount, uint256 timestamp);

    //  MODIFIERS
    modifier onlyNewStudent(address _addr) {
        require(!students[_addr].exists, "Student already registered");
        _;
    }

    modifier onlyExistingStudent(address _addr) {
        require(students[_addr].exists, "Student not found");
        _;
    }

    modifier onlyNewStaff(address _addr) {
        require(!staffs[_addr].exists, "Staff already registered");
        _;
    }

    modifier onlyExistingStaff(address _addr) {
        require(staffs[_addr].exists, "Staff not found");
        _;
    }

    //  CONSTRUCTOR
    /// @param initialSupply Total tokens minted to deployer (e.g. 1_000_000)
    constructor(uint256 initialSupply)
        ERC20("SchoolToken", "SKT")
        Ownable(msg.sender)
    {
        _mint(msg.sender, initialSupply * 10 ** decimals());
    }

    //  HELPERS
    /// @notice Returns the fee amount for a given level
    function getFeeForLevel(Level _level) public pure returns (uint256) {
        if (_level == Level.L100) return FEE_L100;
        if (_level == Level.L200) return FEE_L200;
        if (_level == Level.L300) return FEE_L300;
        return FEE_L400;
    }

    //  STUDENT FUNCTIONS
    /// @notice Register a student and pay school fees in one call.
    /// @dev    Student must have approved this contract to spend the fee first.
    /// @param  _name    Full name of the student
    /// @param  _level   Academic level (0 = 100L … 3 = 400L)
    function registerStudent(string calldata _name, Level _level)
        external
        onlyNewStudent(msg.sender)
    {
        uint256 fee = getFeeForLevel(_level);
        require(balanceOf(msg.sender) >= fee, "Insufficient token balance");
        require(allowance(msg.sender, address(this)) >= fee, "Approve contract to spend tokens first");

        // Transfer fee from student to contract
        _transfer(msg.sender, address(this), fee);

        _studentIdCounter++;

        students[msg.sender] = Student({
            id:               _studentIdCounter,
            name:             _name,
            walletAddress:    msg.sender,
            level:            _level,
            paymentStatus:    PaymentStatus.PAID,
            feePaid:          fee,
            paymentTimestamp: block.timestamp,
            exists:           true
        });

        studentList.push(msg.sender);

        emit StudentRegistered(_studentIdCounter, msg.sender, _name, _level);
        emit FeePaid(msg.sender, fee, block.timestamp);
        emit PaymentStatusUpdated(msg.sender, PaymentStatus.PAID, block.timestamp);
    }

    /// @notice Owner can manually update a student's payment status (e.g. after off-chain payment)
    function updatePaymentStatus(address _studentAddr, PaymentStatus _status)
        external
        onlyOwner
        onlyExistingStudent(_studentAddr)
    {
        students[_studentAddr].paymentStatus    = _status;
        students[_studentAddr].paymentTimestamp = block.timestamp;

        emit PaymentStatusUpdated(_studentAddr, _status, block.timestamp);
    }

    /// @notice Get details of a single student
    function getStudent(address _studentAddr)
        external
        view
        onlyExistingStudent(_studentAddr)
        returns (Student memory)
    {
        return students[_studentAddr];
    }

    /// @notice Get all registered students
    function getAllStudents() external view returns (Student[] memory) {
        Student[] memory result = new Student[](studentList.length);
        for (uint256 i = 0; i < studentList.length; i++) {
            result[i] = students[studentList[i]];
        }
        return result;
    }

    /// @notice Total number of registered students
    function totalStudents() external view returns (uint256) {
        return studentList.length;
    }

    //  STAFF FUNCTIONS

    /// @notice Register a staff member (only owner / admin)
    /// @param  _staffAddr  Wallet address of the staff
    /// @param  _name       Full name
    /// @param  _role       Job role (e.g. "Teacher", "Admin")
    /// @param  _salary     Monthly salary in full tokens (e.g. 500 = 500 SKT)
    function registerStaff(
        address _staffAddr,
        string  calldata _name,
        string  calldata _role,
        uint256 _salary
    )
        external
        onlyOwner
        onlyNewStaff(_staffAddr)
    {
        require(_staffAddr != address(0), "Invalid address");
        require(_salary > 0, "Salary must be greater than 0");

        _staffIdCounter++;

        staffs[_staffAddr] = Staff({
            id:          _staffIdCounter,
            name:        _name,
            walletAddress: _staffAddr,
            role:        _role,
            salary:      _salary * 10 ** decimals(),
            lastPaidAt:  0,
            exists:      true
        });

        staffList.push(_staffAddr);

        emit StaffRegistered(_staffIdCounter, _staffAddr, _name, _role);
    }

    /// @notice Pay a staff member their salary
    /// @dev    Contract must hold enough tokens (funded from student fees + owner)
    function payStaff(address _staffAddr)
        external
        onlyOwner
        onlyExistingStaff(_staffAddr)
    {
        Staff storage staff = staffs[_staffAddr];
        require(balanceOf(address(this)) >= staff.salary, "Contract has insufficient funds");

        staff.lastPaidAt = block.timestamp;
        _transfer(address(this), _staffAddr, staff.salary);

        emit StaffPaid(_staffAddr, staff.salary, block.timestamp);
    }

    /// @notice Get details of a single staff member
    function getStaff(address _staffAddr)
        external
        view
        onlyExistingStaff(_staffAddr)
        returns (Staff memory)
    {
        return staffs[_staffAddr];
    }

    /// @notice Get all registered staff members
    function getAllStaff() external view returns (Staff[] memory) {
        Staff[] memory result = new Staff[](staffList.length);
        for (uint256 i = 0; i < staffList.length; i++) {
            result[i] = staffs[staffList[i]];
        }
        return result;
    }

    /// @notice Total number of registered staff
    function totalStaff() external view returns (uint256) {
        return staffList.length;
    }

    //  TREASURY FUNCTIONS

    /// @notice Owner can deposit additional tokens into the contract (for payroll)
    function fundContract(uint256 _amount) external onlyOwner {
        require(_amount > 0, "Amount must be > 0");
        _transfer(msg.sender, address(this), _amount * 10 ** decimals());
    }

    /// @notice Owner can withdraw tokens from the contract
    function withdraw(uint256 _amount) external onlyOwner {
        require(balanceOf(address(this)) >= _amount, "Insufficient contract balance");
        _transfer(address(this), msg.sender, _amount);
    }

    /// @notice Check the contract's current token balance (treasury)
    function contractBalance() external view returns (uint256) {
        return balanceOf(address(this));
    }
}
