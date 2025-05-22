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
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .white
        title = "Extract Player Names"
        
        setupImageView()
        setupTableView()
        setupPickImageButton()
    }
    
    @objc func generate() {
        // Example usage:
        if extractedNames.count < 24 {
            return
        }
        if let schedule = generatePadelSchedule(players: extractedNames) {
            let csvURL = exportScheduleToCSV(schedule)
            print("CSV file created at")
            // You can share this file or open it in Numbers/Excel
        }
    }
    
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
        var lastPlayedWith: [String: Int] = [:] // Tracks times played with each teammate
        var lastPlayedAgainst: [String: Int] = [:] // Tracks times played against each opponent
    }
    
    func generatePadelSchedule(players: [String]) -> [TimeSlot]? {
        guard players.count == 24 else {
            print("Error: Exactly 24 players are required")
            return nil
        }
        
        let uniquePlayers = Array(Set(players))
        guard uniquePlayers.count == 24 else {
            print("Error: Player names must be unique")
            return nil
        }
        
        var schedule = [TimeSlot]()
        var playerStats = [String: PlayerSchedule]()
        for player in players {
            playerStats[player] = PlayerSchedule()
        }
        
        // Create 6 time slots
        for timeSlotIndex in 0..<6 {
            // Time formatting
            let startMinutes = 9 * 60 + timeSlotIndex * 20
            let endMinutes = startMinutes + 20

            let startHour = startMinutes / 60
            let startMinute = startMinutes % 60
            let endHour = endMinutes / 60
            let endMinute = endMinutes % 60

            let period = String(format: "%d:%02d - %d:%02d", startHour, startMinute, endHour, endMinute)
            
            //
            var attempts = 0
            let maxAttempts = 500
            
            var timeSlotSuccess = false
            var timeSlotMatches: [Match]?
            var timeSlotRestingPlayers: [String]?
            
            // Try multiple attempts to generate this time slot
            while attempts < maxAttempts && !timeSlotSuccess {
                if let result = tryGenerateTimeSlot(
                    players: players,
                    playerStats: playerStats,
                    timeSlotIndex: timeSlotIndex,
                    previousRestingPlayers: schedule.last?.restingPlayers ?? []
                ) {
                    // Verify this time slot won't cause future violations
                    if validateProposedTimeSlot(
                        result: result,
                        playerStats: playerStats,
                        remainingSlots: 5 - timeSlotIndex
                    ) {
                        timeSlotMatches = result.matches
                        timeSlotRestingPlayers = result.restingPlayers
                        timeSlotSuccess = true
                    }
                }
                attempts += 1
            }
            
            guard let matches = timeSlotMatches, let restingPlayers = timeSlotRestingPlayers else {
                print("Error: Could not generate valid schedule for time slot \(timeSlotIndex + 1)")
                return nil
            }
            
            // Update player stats with the successful time slot
            updatePlayerStats(
                playerStats: &playerStats,
                matches: matches,
                restingPlayers: restingPlayers,
                previousRestingPlayers: schedule.last?.restingPlayers ?? []
            )
            
            schedule.append(TimeSlot(period: period, matches: matches, restingPlayers: restingPlayers))
        }
        
        // Final validation
        for (player, stats) in playerStats {
            guard stats.matchesPlayed == 4 && stats.matchesResting == 2 else {
                print("Validation Error: Player \(player) has \(stats.matchesPlayed) matches and \(stats.matchesResting) rests")
                return nil
            }
        }
        
        return schedule
    }
    
    private func tryGenerateTimeSlot(
        players: [String],
        playerStats: [String: PlayerSchedule],
        timeSlotIndex: Int,
        previousRestingPlayers: [String]
    ) -> (matches: [Match], restingPlayers: [String])? {
        var availablePlayers = players.shuffled()
        var selectedPlayers = [String]()
        var restingPlayers = [String]()
        var matches = [Match]()
        
        // 1. Determine who must rest (played 2 consecutive matches or already played 4 matches)
        var mustRestPlayers = players.filter { player in
            let stats = playerStats[player]!
            return stats.consecutiveMatches >= 2 || stats.matchesPlayed >= 4
        }
        
        // 2. Also prioritize players who have only rested once when they need to rest twice
        let needSecondRest = players.filter { player in
            let stats = playerStats[player]!
            return stats.matchesResting == 1 && stats.matchesPlayed + (5 - timeSlotIndex) > 4
        }
        mustRestPlayers.append(contentsOf: needSecondRest)
        
        // 3. Select 8 resting players
        while restingPlayers.count < 8 {
            // First add must-rest players
            if !mustRestPlayers.isEmpty {
                let player = mustRestPlayers.removeFirst()
                if !restingPlayers.contains(player) && !selectedPlayers.contains(player) {
                    restingPlayers.append(player)
                    continue
                }
            }
            
            // Then add players who need to rest to meet their quota
            if let player = availablePlayers.first(where: { player in
                !restingPlayers.contains(player) &&
                !selectedPlayers.contains(player) &&
                (playerStats[player]!.matchesResting == 0 && playerStats[player]!.matchesPlayed + (6 - timeSlotIndex) > 4)
            }) {
                restingPlayers.append(player)
                continue
            }
            
            // Then add random players who haven't rested twice yet
            if let player = availablePlayers.filter({ player in
                !restingPlayers.contains(player) &&
                !selectedPlayers.contains(player) &&
                playerStats[player]!.matchesResting < 2
            }).randomElement() {
                restingPlayers.append(player)
            } else {
                return nil
            }
        }
        
        // 4. Get playing players (must have played < 4 matches)
        let playingPlayers = players.filter { player in
            !restingPlayers.contains(player) && playerStats[player]!.matchesPlayed < 4
        }.shuffled()
        
        // 5. Create matches for 4 courts
        for court in 1...4 {
            var bestTeamPair: ([String], [String])? = nil
            var bestScore = Int.max
            
            // Try to find the best possible team pairing
            for p1 in playingPlayers where !selectedPlayers.contains(p1) && playerStats[p1]!.matchesPlayed < 4 {
                for p2 in playingPlayers where p2 != p1 && !selectedPlayers.contains(p2) && playerStats[p2]!.matchesPlayed < 4 {
                    for p3 in playingPlayers where p3 != p1 && p3 != p2 && !selectedPlayers.contains(p3) && playerStats[p3]!.matchesPlayed < 4 {
                        for p4 in playingPlayers where p4 != p1 && p4 != p2 && p4 != p3 && !selectedPlayers.contains(p4) && playerStats[p4]!.matchesPlayed < 4 {
                            let team1 = [p1, p2].sorted()
                            let team2 = [p3, p4].sorted()
                            
                            let score = calculateTeamScore(
                                team1: team1,
                                team2: team2,
                                playerStats: playerStats
                            )
                            
                            if score < bestScore {
                                bestScore = score
                                bestTeamPair = (team1, team2)
                            }
                        }
                    }
                }
            }
            
            guard let (team1, team2) = bestTeamPair else {
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
    
    private func calculateTeamScore(
        team1: [String],
        team2: [String],
        playerStats: [String: PlayerSchedule]
    ) -> Int {
        var score = 0
        
        // Check teammate constraints
        for player in team1 {
            if let teammate = team1.first(where: { $0 != player }) {
                let playedWithCount = playerStats[player]?.lastPlayedWith[teammate] ?? 0
                if playedWithCount >= 2 {
                    score += 100 // Penalize playing with same teammate too much
                } else {
                    score += playedWithCount * 10
                }
            }
        }
        
        for player in team2 {
            if let teammate = team2.first(where: { $0 != player }) {
                let playedWithCount = playerStats[player]?.lastPlayedWith[teammate] ?? 0
                if playedWithCount >= 2 {
                    score += 100
                } else {
                    score += playedWithCount * 10
                }
            }
        }
        
        // Check opponent constraints
        for player in team1 {
            for opponent in team2 {
                let playedAgainstCount = playerStats[player]?.lastPlayedAgainst[opponent] ?? 0
                if playedAgainstCount >= 3 {
                    score += 50 // Penalize playing against same opponent too much
                } else {
                    score += playedAgainstCount * 5
                }
            }
        }
        
        // Add score based on how many matches players have left
        for player in team1 + team2 {
            let matchesLeft = 4 - (playerStats[player]?.matchesPlayed ?? 0)
            score += (6 - matchesLeft) * 2 // Prefer players with more matches left
        }
        
        return score
    }
    
    private func validateProposedTimeSlot(
        result: (matches: [Match], restingPlayers: [String]),
        playerStats: [String: PlayerSchedule],
        remainingSlots: Int
    ) -> Bool {
        // Make sure no player will exceed their match limit
        for player in result.restingPlayers {
            let currentMatches = playerStats[player]?.matchesPlayed ?? 0
            if currentMatches + remainingSlots < 4 {
                // This player needs to play in future slots but is resting now
                return false
            }
        }
        
        // Check players who are playing
        var tempStats = playerStats
        for match in result.matches {
            for player in [match.team1.0, match.team1.1, match.team2.0, match.team2.1] {
                tempStats[player]?.matchesPlayed += 1
                if tempStats[player]?.matchesPlayed ?? 0 > 4 {
                    return false
                }
            }
        }
        
        return true
    }
    
    private func updatePlayerStats(
        playerStats: inout [String: PlayerSchedule],
        matches: [Match],
        restingPlayers: [String],
        previousRestingPlayers: [String]
    ) {
        // Update playing players
        for match in matches {
            let team1 = [match.team1.0, match.team1.1]
            let team2 = [match.team2.0, match.team2.1]
            
            for player in team1 + team2 {
                playerStats[player]?.matchesPlayed += 1
                
                // Update consecutive matches
                if previousRestingPlayers.contains(player) {
                    playerStats[player]?.consecutiveMatches = 1
                } else {
                    playerStats[player]?.consecutiveMatches += 1
                }
                
                // Update teammate history
                let teammate = team1.contains(player) ?
                team1.first { $0 != player }! :
                team2.first { $0 != player }!
                playerStats[player]?.lastPlayedWith[teammate, default: 0] += 1
                
                // Update opponent history
                let opponents = team1.contains(player) ? team2 : team1
                for opponent in opponents {
                    playerStats[player]?.lastPlayedAgainst[opponent, default: 0] += 1
                }
            }
        }
        
        // Update resting players
        for player in restingPlayers {
            playerStats[player]?.matchesResting += 1
            playerStats[player]?.consecutiveMatches = 0
        }
    }
    
    // Helper function to print the schedule
    func printSchedule(_ schedule: [TimeSlot]) {
        for timeSlot in schedule {
            print("\n\(timeSlot.period):")
            print("Resting: \(timeSlot.restingPlayers.joined(separator: ", "))")
            
            for match in timeSlot.matches {
                print("Court \(match.court): \(match.team1.0) & \(match.team1.1) vs \(match.team2.0) & \(match.team2.1)")
            }
        }
    }
    
    func exportScheduleToCSV(_ schedule: [TimeSlot], fileName: String = "padel_schedule") -> Bool {
        // Create CSV header
        var csvString = "Time Period,Court 1,Court 2,Court 3,Court 4,Resting Players\n"
        
        for timeSlot in schedule {
            var row: [String] = []
            row.append("\"\(timeSlot.period)\"")
            
            // Prepare matches for courts 1–4 (even if some are missing)
            var courtMatches: [Int: Match] = [:]
            for match in timeSlot.matches {
                courtMatches[match.court] = match
            }
            
            for court in 1...4 {
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
