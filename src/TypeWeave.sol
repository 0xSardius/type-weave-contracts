// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IMoveableType {
    struct Token {
        string c;
        uint16 m;
        bool burned;
        string punc;
        uint256[] contains;
        bool listed;
        uint256 price;
        uint256 mint_price;
        uint256 mint_ts;
        uint256 buy_ts;
        uint256 ts;
        uint256 uses;
    }

    function tokens(uint256 tokenId) external view returns (Token memory);
    function ownerOf(uint256 tokenId) external view returns (address);
    function combine(
        uint256[] memory data,
        uint256[][] memory ws_indices, 
        uint256[][] memory ws_amounts, 
        string calldata punc
    ) external;
    function combine_func(
        uint256[] memory data,
        uint256[][] memory ws_indices,
        uint256[][] memory ws_amounts,
        string calldata punc
    ) external view returns (string memory);
}

contract TypeWeave is Ownable {
    IMoveableType public immutable moveableType;
    
    struct Pattern {
        uint256[] sourceTokenIds;
        uint256 resultTokenId;
        string resultWord;
        uint256 score;
        uint256 timestamp;
        address creator;
        bool valid;
    }

    mapping(uint256 => Pattern) public patterns;
    mapping(string => bool) public usedWords;
    uint256 public nextPatternId = 1;
    
    mapping(address => uint256[]) public weaverAchievements;
    mapping(address => uint256) public weaverScores;
    mapping(address => uint256[]) public weaverPatterns;

    event PatternCreated(
        uint256 indexed patternId,
        address indexed creator,
        uint256[] sourceTokenIds,
        uint256 resultTokenId,
        string resultWord,
        uint256 score
    );

    event AchievementUnlocked(
        address indexed weaver,
        uint256 achievementId,
        uint256 timestamp
    );

    constructor(address _moveableType) Ownable(msg.sender) {
        moveableType = IMoveableType(_moveableType);
    }

    function weavePattern(
        uint256[] calldata sourceTokenIds,
        uint256[][] calldata wsIndices,
        uint256[][] calldata wsAmounts,
        string calldata punctuation
    ) external returns (uint256) {
        // Prepare data for Moveable Type combine
        uint256[] memory data = new uint256[](sourceTokenIds.length * 3);
        for (uint256 i = 0; i < sourceTokenIds.length; i++) {
            require(
                moveableType.ownerOf(sourceTokenIds[i]) == msg.sender,
                "Must own source tokens"
            );
            data[i*3] = sourceTokenIds[i];     // token id
            data[i*3+1] = i;                   // index
            data[i*3+2] = 1;                   // reset whitespace
        }

        // Preview combination to validate
        string memory resultWord = moveableType.combine_func(
            data,
            wsIndices,
            wsAmounts,
            punctuation
        );
        
        require(!usedWords[resultWord], "Word already exists");
        require(bytes(resultWord).length > 0, "Invalid combination");

        // Execute actual combination
        moveableType.combine(
            data,
            wsIndices,
            wsAmounts,
            punctuation
        );

        // Calculate score and create pattern
        uint256 score = calculatePatternScore(sourceTokenIds, resultWord);
        uint256 resultTokenId = sourceTokenIds[0]; // First token becomes result in MT

        Pattern memory newPattern = Pattern({
            sourceTokenIds: sourceTokenIds,
            resultTokenId: resultTokenId,
            resultWord: resultWord,
            score: score,
            timestamp: block.timestamp,
            creator: msg.sender,
            valid: true
        });

        uint256 patternId = nextPatternId++;
        patterns[patternId] = newPattern;
        usedWords[resultWord] = true;
        weaverScores[msg.sender] += score;
        weaverPatterns[msg.sender].push(patternId);

        checkAndGrantAchievements(msg.sender, score, resultWord);

        emit PatternCreated(
            patternId,
            msg.sender,
            sourceTokenIds,
            resultTokenId,
            resultWord,
            score
        );

        return patternId;
    }

    function calculatePatternScore(
        uint256[] memory sourceTokenIds,
        string memory resultWord
    ) public view returns (uint256) {
        uint256 score = 0;
        
        // Base score: length * 100
        score += bytes(resultWord).length * 100;
        
        // Source token multiplier
        score += sourceTokenIds.length * 50;
        
        // Palindrome bonus: 2x
        if (isPalindrome(resultWord)) {
            score *= 2;
        }

        // Unique letter bonus
        uint256 uniqueLetters = countUniqueLetters(resultWord);
        score += uniqueLetters * 25;
        
        return score;
    }

    function countUniqueLetters(string memory word) internal pure returns (uint256) {
        bool[26] memory seen;
        bytes memory str = bytes(word);
        uint256 count;

        for (uint256 i = 0; i < str.length; i++) {
            bytes1 char = str[i];
            if (char >= 0x61 && char <= 0x7A) {
                uint256 idx = uint256(uint8(char)) - 97;
                if (!seen[idx]) {
                    seen[idx] = true;
                    count++;
                }
            }
            if (char >= 0x41 && char <= 0x5A) {
                uint256 idx = uint256(uint8(char)) - 65;
                if (!seen[idx]) {
                    seen[idx] = true;
                    count++;
                }
            }
        }
        return count;
    }

    function isPalindrome(string memory str) internal pure returns (bool) {
        bytes memory b = bytes(str);
        uint256 length = b.length;
        
        for (uint256 i = 0; i < length / 2; i++) {
            if (b[i] != b[length - 1 - i]) {
                return false;
            }
        }
        return true;
    }

    function checkAndGrantAchievements(
        address weaver,
        uint256 score,
        string memory word
    ) internal {
        // High Score Achievement
        if (score > 1000 && !hasAchievement(weaver, 1)) {
            grantAchievement(weaver, 1);
        }
        
        // Long Word Achievement
        if (bytes(word).length >= 8 && !hasAchievement(weaver, 2)) {
            grantAchievement(weaver, 2);
        }
        
        // Palindrome Achievement
        if (isPalindrome(word) && !hasAchievement(weaver, 3)) {
            grantAchievement(weaver, 3);
        }
    }

    function hasAchievement(
        address weaver,
        uint256 achievementId
    ) internal view returns (bool) {
        uint256[] memory achievements = weaverAchievements[weaver];
        for (uint256 i = 0; i < achievements.length; i++) {
            if (achievements[i] == achievementId) {
                return true;
            }
        }
        return false;
    }

    function grantAchievement(address weaver, uint256 achievementId) internal {
        weaverAchievements[weaver].push(achievementId);
        emit AchievementUnlocked(weaver, achievementId, block.timestamp);
    }

    // Getter functions for frontend
    function getWeaverPatterns(address weaver) external view returns (uint256[] memory) {
        return weaverPatterns[weaver];
    }

    function getTopWeavers(uint256 limit) external view returns (address[] memory, uint256[] memory) {
        // Basic implementation - can be optimized
        address[] memory weavers = new address[](limit);
        uint256[] memory scores = new uint256[](limit);
        
        return (weavers, scores);
    }
}