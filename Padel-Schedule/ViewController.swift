//
//  ViewController.swift
//  Padel-Schedule
//
//  Created by Mostafa Sayed on 14/05/2025.
//

import UIKit
import Vision

class ViewController: UIViewController {
    
    let imageView = UIImageView()
    let tableView = UITableView()
    var extractedNames: [String] = []
    
    // Total time slots calculation (3 hours = 9 * 20-minute slots)
    let totalSlots = 9
    let matchesPerPlayer = 6
    let restsPerPlayer = 3

    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .white
        title = "Extract Player Names"
        
        setupImageView()
        setupTableView()
        setupPickImageButton()
//        generate()
    }
    
    @objc func generate() {
        // Example usage:
        
//        extractedNames = (1...30).map { "Player \($0)" }
        if extractedNames.count < 30 {
            return
        }
        print("Starting")
        if let schedule = generatePadelSchedule(players: extractedNames) {
            print("Scheduel created")
            let csvURL = exportScheduleToCSV(schedule)
            print("CSV file created at")
            // You can share this file or open it in Numbers/Excel
        } else {
            print("Failed!")
        }
    }
    
    // MARK: - Data Structures
    struct Match {
        let team1: (String, String)
        let team2: (String, String)
        let court: Int
    }

    struct TimeSlot {
        let period: String
        let matches: [Match]
        let restingPlayers: [String]
    }

    struct PlayerSchedule {
        var matchesPlayed: Int = 0
        var matchesResting: Int = 0
        var consecutiveMatches: Int = 0
        var consecutiveRests: Int = 0
        var lastPlayedWith: [String: Int] = [:]
        var lastPlayedAgainst: [String: Int] = [:]
    }

    // MARK: - Main Function
    func generatePadelSchedule(players: [String]) -> [TimeSlot]? {
        guard players.count == 30 else {
            print("Error: Exactly 30 players required")
            return nil
        }
        
        let uniquePlayers = Array(Set(players))
        guard uniquePlayers.count == 30 else {
            print("Error: Duplicate player names")
            return nil
        }
        
        var schedule = [TimeSlot]()
        var playerStats = [String: PlayerSchedule]()
        players.forEach { playerStats[$0] = PlayerSchedule() }
        
        let totalSlots = 9 // 3 hours = 9 × 20-minute slots
        let matchesPerPlayer = 6
        let restsPerPlayer = 3
        
        for timeSlotIndex in 0..<totalSlots {
            print("INDEXNum ", timeSlotIndex)
            let period = "\(timeSlotIndex * 20 + 1)-\((timeSlotIndex + 1) * 20) minutes"
            var attempts = 0
            let maxAttempts = 1000
            
            var timeSlot: (matches: [Match], restingPlayers: [String])?
            
            while attempts < maxAttempts && timeSlot == nil {
                print("attempt ", attempts)
                timeSlot = tryGenerateTimeSlot(
                    players: players,
                    playerStats: playerStats,
                    timeSlotIndex: timeSlotIndex,
                    previousRestingPlayers: schedule.last?.restingPlayers ?? []
                )
                attempts += 1
            }
            
            guard let (matches, restingPlayers) = timeSlot else {
                print("Failed to generate time slot \(timeSlotIndex + 1)")
                return nil
            }
            
            updatePlayerStats(
                playerStats: &playerStats,
                matches: matches,
                restingPlayers: restingPlayers,
                previousRestingPlayers: schedule.last?.restingPlayers ?? []
            )
            
            schedule.append(TimeSlot(
                period: period,
                matches: matches,
                restingPlayers: restingPlayers
            ))
        }
        
        // Final validation
        for (player, stats) in playerStats {
            guard stats.matchesPlayed == matchesPerPlayer && stats.matchesResting == restsPerPlayer else {
                print("Validation failed for \(player): \(stats.matchesPlayed) matches, \(stats.matchesResting) rests")
                return nil
            }
        }
        debugValidate(schedule, players: players)
        return schedule
    }

    // MARK: - Helper Functions
    private func tryGenerateTimeSlot(
        players: [String],
        playerStats: [String: PlayerSchedule],
        timeSlotIndex: Int,
        previousRestingPlayers: [String]
    ) -> (matches: [Match], restingPlayers: [String])? {
        let requiredResting = 10
        var restingPlayers = [String]()
        var selectedPlayers = [String]()
        var matches = [Match]()
        
        // 1. Calculate remaining needs
        let remainingSlots = 8 - timeSlotIndex // 0-based index
        
        // 2. Priority: Players who MUST rest to complete their 3 rests
        let mustRestNow = players.filter {
            let neededRests = 3 - playerStats[$0]!.matchesResting
            return neededRests > 0 && neededRests >= remainingSlots
        }
        
        // 3. Add must-rest players first
        restingPlayers.append(contentsOf: mustRestNow.prefix(requiredResting))
        
        // 4. Fill remaining rests with players needing rests
        if restingPlayers.count < requiredResting {
            let additionalNeeded = requiredResting - restingPlayers.count
            let candidates = players
                .filter { !restingPlayers.contains($0) }
                .filter { !previousRestingPlayers.contains($0) }
                .filter { playerStats[$0]!.matchesResting < 2 } // Prefer players who still can rest
                .sorted { playerStats[$0]!.matchesResting > playerStats[$1]!.matchesResting }
            
            restingPlayers.append(contentsOf: candidates.prefix(additionalNeeded))
        }
        
        // 5. Final fallback if still not enough
        if restingPlayers.count < requiredResting {
            let remaining = players
                .filter { !restingPlayers.contains($0) }
                .filter { !previousRestingPlayers.contains($0) }
                .prefix(requiredResting - restingPlayers.count)
            restingPlayers.append(contentsOf: remaining)
        }
        
        // 6. Get playing players with remaining capacity
        let playingPlayers = players
            .filter { !restingPlayers.contains($0) }
            .filter { playerStats[$0]!.matchesPlayed < 6 }
        
        // 7. Emergency override for final slots
        if timeSlotIndex >= 6 { // Last 3 slots
            return emergencySlotGeneration(
                players: players,
                playingPlayers: playingPlayers,
                restingPlayers: restingPlayers,
                playerStats: playerStats
            )
        }
        
        // 7. Create matches with improved team selection
        for court in 1...5 {
            var bestScore = Int.max
            var bestTeams: ([String], [String])? = nil
            
            // Try all combinations of available players
            for p1 in playingPlayers where !selectedPlayers.contains(p1) {
                for p2 in playingPlayers where p2 > p1 && !selectedPlayers.contains(p2) {
                    let remaining = playingPlayers
                        .filter { $0 != p1 && $0 != p2 }
                        .filter { !selectedPlayers.contains($0) }
                    
                    for p3 in remaining {
                        for p4 in remaining where p4 > p3 {
                            let team1 = [p1, p2].sorted()
                            let team2 = [p3, p4].sorted()
                            
                            let score = calculateTeamScore(
                                team1: team1,
                                team2: team2,
                                playerStats: playerStats
                            )
                            
                            if score < bestScore {
                                bestScore = score
                                bestTeams = (team1, team2)
                            }
                        }
                    }
                }
            }
            
            guard let (team1, team2) = bestTeams else {
                return nil
            }
            
            matches.append(Match(
                team1: (team1[0], team1[1]),
                team2: (team2[0], team2[1]),
                court: court
            ))
            
            selectedPlayers.append(contentsOf: team1)
            selectedPlayers.append(contentsOf: team2)
        }
        
        return (matches, restingPlayers)
    }
    
    private func emergencySlotGeneration(
        players: [String],
        playingPlayers: [String],
        restingPlayers: [String],
        playerStats: [String: PlayerSchedule]
    ) -> (matches: [Match], restingPlayers: [String])? {
        var matches = [Match]()
        var availablePlayers = playingPlayers.shuffled()
        
        for court in 1...5 {
            guard availablePlayers.count >= 4 else { return nil }
            
            let team1 = Array(availablePlayers.prefix(2))
            let team2 = Array(availablePlayers[2..<4])
            availablePlayers = Array(availablePlayers.dropFirst(4))
            
            matches.append(Match(
                team1: (team1[0], team1[1]),
                team2: (team2[0], team2[1]),
                court: court
            ))
        }
        
        return (matches, restingPlayers)
    }

    private func calculateTeamScore(
        team1: [String],
        team2: [String],
        playerStats: [String: PlayerSchedule]
    ) -> Int {
        var score = 0
        
        // 1. Calculate partner penalty
        let partnerPenalty = [team1, team2].reduce(0) { acc, team in
            acc + team.reduce(0) { innerAcc, player in
                let partner = team.first { $0 != player }!
                return innerAcc + (playerStats[player]!.lastPlayedWith[partner] ?? 0)
            }
        }
        score += partnerPenalty * 100
        
        // 2. Calculate opponent penalty in separate steps
        let team1vsTeam2 = team1.reduce(0) { acc, player in
            acc + team2.reduce(0) { innerAcc, opponent in
                innerAcc + (playerStats[player]!.lastPlayedAgainst[opponent] ?? 0)
            }
        }
        
        let team2vsTeam1 = team2.reduce(0) { acc, player in
            acc + team1.reduce(0) { innerAcc, opponent in
                innerAcc + (playerStats[player]!.lastPlayedAgainst[opponent] ?? 0)
            }
        }
        
        let opponentPenalty = team1vsTeam2 + team2vsTeam1
        score += opponentPenalty * 50
        
        // 3. Match balance bonus
        let balanceBonus = (team1 + team2).reduce(0) {
            $0 + (6 - playerStats[$1]!.matchesPlayed)
        }
        score -= balanceBonus * 20
        
        // 4. Consecutive match penalty
        let consecutivePenalty = (team1 + team2).reduce(0) {
            $0 + (playerStats[$1]!.consecutiveMatches >= 2 ? 100 : 0)
        }
        score += consecutivePenalty
        
        return score
    }

    private func updatePlayerStats(
        playerStats: inout [String: PlayerSchedule],
        matches: [Match],
        restingPlayers: [String],
        previousRestingPlayers: [String]
    ) {
        // Update players who played
        for match in matches {
            let participants = [match.team1.0, match.team1.1, match.team2.0, match.team2.1]
            
            for player in participants {
                playerStats[player]?.matchesPlayed += 1
                playerStats[player]?.consecutiveMatches += 1
                playerStats[player]?.consecutiveRests = 0
                
                // Update teammate history
                let teammate = participants.first { $0 != player }!
                playerStats[player]?.lastPlayedWith[teammate, default: 0] += 1
                
                // Update opponent history
                let opponents = participants.filter { $0 != player && $0 != teammate }
                for opponent in opponents {
                    playerStats[player]?.lastPlayedAgainst[opponent, default: 0] += 1
                }
            }
        }
        
        // Update resting players
        for player in restingPlayers {
            playerStats[player]?.matchesResting += 1
            playerStats[player]?.consecutiveRests += 1
            playerStats[player]?.consecutiveMatches = 0
        }
    }

    // MARK: - Output
    func printSchedule(_ schedule: [TimeSlot]) {
        for slot in schedule {
            print("\nTime Slot: \(slot.period)")
            print("Resting: \(slot.restingPlayers.joined(separator: ", "))")
            
            for match in slot.matches {
                print("Court \(match.court): \(match.team1.0)/\(match.team1.1) vs \(match.team2.0)/\(match.team2.1)")
            }
        }
    }

    func debugValidate(_ schedule: [TimeSlot], players: [String]) {
        var matchCounts = [String: Int]()
        var restCounts = [String: Int]()
        
        for (index, slot) in schedule.enumerated() {
            // Check court count
            assert(slot.matches.count == 5, "Time Slot \(index) has \(slot.matches.count) courts")
            
            // Check player counts
            let playingPlayers = slot.matches.flatMap { [$0.team1.0, $0.team1.1, $0.team2.0, $0.team2.1] }
            assert(playingPlayers.count == 20, "Time Slot \(index) has \(playingPlayers.count) playing players")
            assert(Set(playingPlayers).count == 20, "Duplicate players in time slot \(index)")
            
            // Track rests
            for p in slot.restingPlayers {
                restCounts[p, default: 0] += 1
                if index > 0 && schedule[index-1].restingPlayers.contains(p) {
                    fatalError("Player \(p) rested consecutively in slots \(index-1) and \(index)")
                }
            }
            
            // Track matches
            for p in playingPlayers {
                matchCounts[p, default: 0] += 1
            }
        }
        
        // Final counts
        for player in players {
            assert(matchCounts[player] == 6, "Player \(player) has \(matchCounts[player] ?? 0) matches")
            assert(restCounts[player] == 3, "Player \(player) has \(restCounts[player] ?? 0) rests")
        }
        print("All validation passed!")
    }
    
    func exportScheduleToCSV(_ schedule: [TimeSlot], fileName: String = "padel_schedule") -> Bool {
        // Create CSV header
        var csvString = "Time Period,Court 1,Court 2,Court 3,Court 4, Court 5,Resting Players\n"
        
        for timeSlot in schedule {
            var row: [String] = []
            row.append("\"\(timeSlot.period)\"")
            
            // Prepare matches for courts 1–4 (even if some are missing)
            var courtMatches: [Int: Match] = [:]
            for match in timeSlot.matches {
                courtMatches[match.court] = match
            }
            
            for court in 1...5 {
                if let match = courtMatches[court] {
                    let matchText = """
                    \(match.team1.0) + \(match.team1.1)
                    VS
                    \(match.team2.0) + \(match.team2.1)
                    """
                    row.append("\"\(matchText)\"")
                } else {
                    row.append("\"\"")
                }
            }
            
            let restingText = timeSlot.restingPlayers.joined(separator: " | ")
            row.append("\"\(restingText)\"")
            
            csvString.append(row.joined(separator: ",") + "\n")
        }

        // Save to file
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return false
        }
        
        let fileURL = documentsURL.appendingPathComponent("\(fileName).csv")
        
        do {
            try csvString.write(to: fileURL, atomically: true, encoding: .utf8)
            let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            UIApplication.shared.windows.first?.rootViewController?.present(activityVC, animated: true)
            return true
        } catch {
            print("Error writing CSV file: \(error)")
            return false
        }
    }

    @IBAction func loadImage(_ sender: Any) {
    }
}

// Mark: UI Setup
extension ViewController {
    func setupImageView() {
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .secondarySystemBackground
        view.addSubview(imageView)
        
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            imageView.heightAnchor.constraint(equalToConstant: 200)
        ])
    }
    
    func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 16),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16)
        ])
    }
    
    func setupPickImageButton() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Pick Image", style: .plain, target: self, action: #selector(pickImage))

        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Generate CSV", style: .plain, target: self, action: #selector(generate))
    }
}
extension ViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate, UITableViewDataSource  {
    @objc func pickImage() {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = self
        present(picker, animated: true)
    }
    
    // MARK: - UIImagePickerControllerDelegate
    
    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true)
        
        if let image = info[.originalImage] as? UIImage {
            imageView.image = image
            extractPlayerNames(from: image)
        }
    }
    
    func extractPlayerNames(from image: UIImage) {
        guard let cgImage = image.cgImage else { return }
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Text recognition error: \(error)")
                return
            }
            
            var names: [String] = []
            
            for observation in request.results as? [VNRecognizedTextObservation] ?? [] {
                if let best = observation.topCandidates(1).first {
                    let raw = best.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // Remove leading number, dot, dash, etc.
                    let noPrefix = raw.replacingOccurrences(of: #"^\d+[-.\s]*"#, with: "", options: .regularExpression)
                    
                    // Remove all non-letters/spaces (including emojis, special chars)
                    let filtered = noPrefix.filter { $0.isLetter || $0.isWhitespace }
                    
                    // Trim whitespace and correct multiple spaces
                    let clean = filtered
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    
                    // Remove suspicious trailing "v" or "V"
                    let cleaned = clean.replacingOccurrences(of: #"[vV]\s*$"#, with: "", options: .regularExpression)
                    
                    if cleaned.count > 1 {
                        names.append(cleaned)
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.extractedNames = names
                self.tableView.reloadData()
            }
        }
        
        request.recognitionLevel = .accurate
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try requestHandler.perform([request])
            } catch {
                print("Failed to perform OCR: \(error)")
            }
        }
    }
    
    // MARK: - UITableViewDataSource
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        extractedNames.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = extractedNames[indexPath.row]
        return cell
    }
}
