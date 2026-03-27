//
//  Helpers.swift
//  MezonChat
//
//  Created by Tran Le Huy Hoang on 17/3/26.
//
import Foundation

func safeJsonDecode<T: Decodable>(
    _ jsonString: String,
    to type: T.Type,
    fallback: T? = nil,
    logError: Bool = false
) -> T? {
    guard !jsonString.isEmpty,
          jsonString != "null",
          let data = jsonString.data(using: .utf8) else {
        if logError {
            print("Invalid UTF8 string")
        }
        return fallback
    }

    do {
        return try JSONDecoder().decode(T.self, from: data)
    } catch {
        if logError {
            print("Decode error:", error)
            print("JSON:", jsonString)
        }
        return fallback
    }
}

