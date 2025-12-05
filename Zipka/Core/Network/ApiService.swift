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

class DataFetcher {

    private let ztpURL = URL(string: "https://gtfs.ztp.krakow.pl")
    private let positionResource = "VehiclePositions.pb"
    
    func createRequest(baseURL: URL, resource: String) -> URLRequest{
        return URLRequest(url: URL(string: resource, relativeTo: baseURL)!)
    }

    func fetchData(request: URLRequest, completion: @escaping (TransitRealtime_FeedMessage?) -> Void){
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("An error occurred while fetching data: \(error)")
                completion(nil)
                return
            }
            guard let data = data else {
                print("No data")
                completion(nil)
                return
            }
                
            do {
                let feedMessage = try TransitRealtime_FeedMessage(serializedBytes: data)
                completion(feedMessage)
            } catch {
                print("An error occurred while fetching data: \(error)")
                completion(nil)
                return
            }
        }
        task.resume()
    }

    func fetchDataAsync(request: URL) async throws -> TransitRealtime_FeedMessage{
        let (data, _) = try await URLSession.shared.data(from: request)
        do {
            let feedMessage = try TransitRealtime_FeedMessage(serializedBytes: data)
            return feedMessage
        } catch {
            throw fetchError.runtimeError("An error occurred while fetching data: \(error)")
        }

    }

}
