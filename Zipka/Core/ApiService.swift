//
//  dataFetcher.swift
//  Zipka
//
//  Created by Jakub Majka on 4/12/25.
//

import Foundation
import SwiftProtobuf
import ZIpkaProtobuf

enum fetchError: Error {
    case runtimeError(String)
}

class ApiService {

    private let baseURL = URL(string: "https://gtfs.ztp.krakow.pl")!
    private let positionResource = "VehiclePositions.pb"
    
    
    private func createRequest(_ baseURL: URL, _ resource: String) -> URLRequest{
        return URLRequest(url: URL(string: resource, relativeTo: baseURL)!)
    }
    
    private var busRequest: URLRequest{
        createRequest(baseURL, "VehiclePositions_A.pb")
    }
    private var tramRequest: URLRequest{
        createRequest(baseURL, "VehiclePositions_T.pb")
    }
    
//    private var
    
//    func fetchRealtimeData(request: URLRequest, completion: @escaping (TransitRealtime_FeedMessage?) -> Void){
//        let task = URLSession.shared.dataTask(with: request) { data, response, error in
//            if let error = error {
//                print("An error occurred while fetching data: \(error)")
//                completion(nil)
//                return
//            }
//            guard let data = data else {
//                print("No data")
//                completion(nil)
//                return
//            }
//                
//            do {
//                let feedMessage = try TransitRealtime_FeedMessage(serializedBytes: data)
//                completion(feedMessage)
//            } catch {
//                print("An error occurred while fetching data: \(error)")
//                completion(nil)
//                return
//            }
//        }
//        task.resume()
//    }

    func fetchRealtimeDataAsync(request: URL) async throws -> TransitRealtime_FeedMessage{
        let (data, _) = try await URLSession.shared.data(from: request)
        do {
            let feedMessage = try TransitRealtime_FeedMessage(serializedBytes: data)
            return feedMessage
        } catch {
            throw fetchError.runtimeError("An error occurred while fetching data: \(error)")
        }

    }

}
