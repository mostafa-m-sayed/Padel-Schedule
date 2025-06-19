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
        if extractedNames.count < 12 {
            return
        }
        if let schedule = generatePadelSchedule(players: extractedNames) {
            let csvURL = exportScheduleToCSV(schedule)
            print("CSV file created")
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
        var consecutiveRests: Int = 0
        var lastPlayedWith: [String: Int] = [:]
        var lastPlayedAgainst: [String: Int] = [:]
    }

    func generatePadelSchedule(players: [String]) -> [TimeSlot]? {
        guard players.count == 12 else {
            print("Error: Exactly 12 players are required")
            return nil
        }
        
        let uniquePlayers = Array(Set(players))
        guard uniquePlayers.count == 12 else {
            print("Error: Player names must be unique")
            return nil
        }
        
        var schedule = [TimeSlot]()
        var playerStats = [String: PlayerSchedule]()
        for player in players {
            playerStats[player] = PlayerSchedule()
        }
        
        // Create 9 time slots (3 hours)
        for timeSlotIndex in 0..<9 {
            // Time formatting
            let startMinutes = 9 * 60 + timeSlotIndex * 20
            let endMinutes = startMinutes + 20

            let startHour = startMinutes / 60
            let startMinute = startMinutes % 60
            let endHour = endMinutes / 60
            let endMinute = endMinutes % 60

            let period = String(format: "%d:%02d - %d:%02d", startHour, startMinute, endHour, endMinute)
            
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
                    timeSlotMatches = result.matches
                    timeSlotRestingPlayers = result.restingPlayers
                    timeSlotSuccess = true
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
            guard stats.matchesPlayed == 6 && stats.matchesResting == 3 else {
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
        
        // 1. Players who must rest (played 2 consecutive matches or already played 6 matches)
        var mustRestPlayers = players.filter { player in
            let stats = playerStats[player]!
            return stats.consecutiveMatches >= 2 || stats.matchesPlayed >= 6
        }
        
        // 2. Players who need to rest to complete their 3 rests
        let needRest = players.filter { player in
            let stats = playerStats[player]!
            return stats.matchesResting < 3 && stats.consecutiveRests < 1
        }
        mustRestPlayers.append(contentsOf: needRest)
        
        // 3. Avoid players who rested last time
        let cannotRestNow = previousRestingPlayers
        
        // 4. Select 4 resting players (12 players - 8 playing)
        while restingPlayers.count < 4 {
            // First add must-rest players
            if !mustRestPlayers.isEmpty {
                let player = mustRestPlayers.removeFirst()
                if !restingPlayers.contains(player) && !cannotRestNow.contains(player) {
                    restingPlayers.append(player)
                    continue
                }
            }
            
            // Then add random players who need rests
            if let player = availablePlayers.first(where: { player in
                !restingPlayers.contains(player) &&
                !cannotRestNow.contains(player) &&
                playerStats[player]!.matchesResting < 3
            }) {
                restingPlayers.append(player)
            } else {
                // Fallback to any available player
                if let player = players.filter({
                    !restingPlayers.contains($0) && !cannotRestNow.contains($0)
                }).randomElement() {
                    restingPlayers.append(player)
                } else {
                    return nil
                }
            }
        }
        
        // 5. Get playing players (must have played < 6 matches)
        let playingPlayers = players.filter { player in
            !restingPlayers.contains(player) && playerStats[player]!.matchesPlayed < 6
        }.shuffled()
        
        // 6. Create matches for 2 courts
        for court in 1...2 {
            var bestTeamPair: ([String], [String])? = nil
            var bestScore = Int.max
            
            // Try to find the best possible team pairing
            for p1 in playingPlayers where !selectedPlayers.contains(p1) {
                for p2 in playingPlayers where p2 != p1 && !selectedPlayers.contains(p2) {
                    for p3 in playingPlayers where p3 != p1 && p3 != p2 && !selectedPlayers.contains(p3) {
                        for p4 in playingPlayers where p4 != p1 && p4 != p2 && p4 != p3 && !selectedPlayers.contains(p4) {
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
        
        // Teammate history
        for player in team1 {
            if let teammate = team1.first(where: { $0 != player }) {
                let playedWithCount = playerStats[player]?.lastPlayedWith[teammate] ?? 0
                score += playedWithCount * 10
            }
        }
        
        for player in team2 {
            if let teammate = team2.first(where: { $0 != player }) {
                let playedWithCount = playerStats[player]?.lastPlayedWith[teammate] ?? 0
                score += playedWithCount * 10
            }
        }
        
        // Opponent history
        for player in team1 {
            for opponent in team2 {
                let playedAgainstCount = playerStats[player]?.lastPlayedAgainst[opponent] ?? 0
                score += playedAgainstCount * 5
            }
        }
        
        // Match balance - prefer players with fewer matches
        for player in team1 + team2 {
            let matchesPlayed = playerStats[player]?.matchesPlayed ?? 0
            score += matchesPlayed * 2
        }
        
        return score
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
                playerStats[player]?.consecutiveMatches += 1
                playerStats[player]?.consecutiveRests = 0
                
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
            playerStats[player]?.consecutiveRests += 1
            playerStats[player]?.consecutiveMatches = 0
        }
    }

    
    
    func exportScheduleToCSV(_ schedule: [TimeSlot], fileName: String = "padel_schedule") -> Bool {
        // Create CSV header
        var csvString = "Time Period,Court 1,Court 2,Resting Players\n"
        print(schedule.count)
        for timeSlot in schedule {
            print("period " + timeSlot.period)
            var row: [String] = []
            row.append("\"\(timeSlot.period)\"")
            
            // Prepare matches for courts 1–2 (even if some are missing)
            var courtMatches: [Int: Match] = [:]
            for match in timeSlot.matches {
                courtMatches[match.court] = match
            }
            
            for court in 1...2 {
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
print("saving")
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
