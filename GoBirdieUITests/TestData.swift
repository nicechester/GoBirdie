//
//  TestShotData.swift
//  GoBirdie
//
//  Created by Kim, Chester on 5/2/26.
//


import Foundation

// Renamed for clarity as test-only utility
public struct TestShotData: Codable {
    public let lat: Double
    public let lon: Double
    public let club: String
    public let club_display: String
}

public struct TestHoleData: Codable {
    public let hole_number: Int
    public let par: Int
    public let score: Int
    public let putts: Int
    public let shots: [TestShotData]
}

public struct TestRoundData: Codable {
    public let course_name: String
    public let total_score: Int
    public let total_putts: Int
    public let holes: [TestHoleData]
}
