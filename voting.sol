// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface INJToken {
    function balanceOf(address account) external view returns (uint256);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

contract VotingContract {
    address public admin;
    INJToken public injToken;

    uint256 public proposalCount;
    uint256 public depositLimit;
    uint256 public depositPeriod;
    uint256 public votingPeriod;

    mapping(uint256 => Proposal) public proposals;
    mapping(address => bool) public vetoHolders;
    mapping(address => bool) public whitelisted; // Whitelisted addresses

    enum ProposalStatus { Pending, Approved, Denied }

    struct Proposal {
        address creator;
        string description;
        uint256 deposit;
        uint256 approvalVotes;
        uint256 denialVotes;
        ProposalStatus status;
        mapping(address => uint256) votes; // Mapping to store the votes of each token holder
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not authorized");
        _;
    }

    modifier onlyTokenHolder() {
        require(injToken.balanceOf(msg.sender) > 0, "Only INJ token holders can participate");
        _;
    }

    modifier onlyVetoHolder() {
        require(vetoHolders[msg.sender], "Only veto holders can perform this action");
        _;
    }

    modifier onlyWhitelisted() {
        require(whitelisted[msg.sender], "Address is not whitelisted");
        _;
    }

    modifier onlyDuringDepositPeriod(uint256 proposalId) {
        require(
            block.timestamp < proposals[proposalId].deposit + depositPeriod,
            "Deposit period has ended"
        );
        _;
    }

    modifier onlyDuringVotingPeriod(uint256 proposalId) {
        require(
            block.timestamp >= proposals[proposalId].deposit + depositPeriod &&
            block.timestamp < proposals[proposalId].deposit + depositPeriod + votingPeriod,
            "Voting period is not active"
        );
        _;
    }

    event ProposalCreated(uint256 proposalId, address creator, string description);
    event DepositMade(uint256 proposalId, address depositor, uint256 amount);
    event ProposalApproved(uint256 proposalId);
    event ProposalDenied(uint256 proposalId);
    event VoteCasted(uint256 proposalId, address voter, uint256 weight, bool approval);

    constructor(
        address _admin,
        address _injToken,
        uint256 _depositLimit,
        uint256 _depositPeriod,
        uint256 _votingPeriod
    ) {
        admin = _admin;
        injToken = INJToken(_injToken);
        depositLimit = _depositLimit;
        depositPeriod = _depositPeriod;
        votingPeriod = _votingPeriod;
    }

    function createProposal(string memory _description) external onlyWhitelisted {
        proposalCount++;
        uint256 proposalId = proposalCount;

        proposals[proposalId].creator = msg.sender;
        proposals[proposalId].description = _description;
        proposals[proposalId].status = ProposalStatus.Pending;

        emit ProposalCreated(proposalId, msg.sender, _description);
    }

    function depositForProposal(uint256 proposalId, uint256 amount)
        external
        onlyWhitelisted
        onlyDuringDepositPeriod(proposalId)
    {
        require(amount > 0, "Deposit amount must be greater than 0");
        require(amount <= depositLimit, "Deposit amount exceeds limit");

        proposals[proposalId].deposit += amount;

        require(
            injToken.transferFrom(msg.sender, address(this), amount),
            "Token transfer failed"
        );

        emit DepositMade(proposalId, msg.sender, amount);

        if (proposals[proposalId].deposit >= depositLimit) {
            proposals[proposalId].deposit = depositLimit;
            proposals[proposalId].status = ProposalStatus.Approved;
        }
    }

    function vote(uint256 proposalId, bool approval) external onlyTokenHolder onlyWhitelisted onlyDuringVotingPeriod(proposalId) {
        require(proposals[proposalId].votes[msg.sender] == 0, "You have already voted");

        uint256 voterBalance = injToken.balanceOf(msg.sender);

        if (approval) {
            proposals[proposalId].approvalVotes += voterBalance;
        } else {
            proposals[proposalId].denialVotes += voterBalance;
        }

        proposals[proposalId].votes[msg.sender] = voterBalance;

        emit VoteCasted(proposalId, msg.sender, voterBalance, approval);
    }


    function finalizeProposal(uint256 proposalId) external onlyAdmin onlyDuringVotingPeriod(proposalId) {
        Proposal storage proposal = proposals[proposalId];

        require(proposal.status == ProposalStatus.Approved || proposal.status == ProposalStatus.Pending, "Invalid proposal status");

        uint256 totalVotes = proposal.approvalVotes + proposal.denialVotes;

        if (proposal.approvalVotes > proposal.denialVotes) {
            proposal.status = ProposalStatus.Approved;
            emit ProposalApproved(proposalId);
        } else {
            proposal.status = ProposalStatus.Denied;
            injToken.transfer(address(0), proposal.deposit);
            emit ProposalDenied(proposalId);
        }
    }

    function setVetoHolder(address holder, bool status) external onlyAdmin {
        vetoHolders[holder] = status;
    }
}
