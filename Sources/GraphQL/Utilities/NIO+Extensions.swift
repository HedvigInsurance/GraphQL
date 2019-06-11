//
//  DictionaryFuture.swift
//  GraphQL
//
//  Created by Jeff Seibert on 3/9/18.
//

import Foundation
import NIO

public typealias Future = EventLoopFuture

extension Collection {
    public func flatten<T>(on eventLoopGroup: EventLoopGroup) -> Future<[T]> where Element == Future<T> {
        return Future.whenAll(Array(self), eventLoop: eventLoopGroup.next())
    }
}

extension Collection {
    public func flatMap<S, T>(
        to type: T.Type,
        on eventLoopGroup: EventLoopGroup,
        _ callback: @escaping ([S]) throws -> Future<T>
    ) -> Future<T> where Element == Future<S> {
        return flatten(on: eventLoopGroup).flatMap(to: T.self, callback)
    }
}

extension Dictionary where Value : FutureType {
    func flatten(on eventLoopGroup: EventLoopGroup) -> Future<[Key: Value.Expectation]> {
        var elements: [Key: Value.Expectation] = [:]

        guard self.count > 0 else {
            return eventLoopGroup.next().newSucceededFuture(result: elements)
        }

        let promise: EventLoopPromise<[Key: Value.Expectation]> = eventLoopGroup.next().newPromise()
        elements.reserveCapacity(self.count)

        for (key, value) in self {
            value.whenSuccess { expectation in
                elements[key] = expectation
                
                if elements.count == self.count {
                    promise.succeed(result: elements)
                }
            }
            
            value.whenFailure { error in
                promise.fail(error: error)
            }
        }

        return promise.futureResult
    }
}
extension Future {
    public func flatMap<T>(
        to type: T.Type = T.self,
        _ callback: @escaping (Expectation) throws -> Future<T>
    ) -> Future<T> {
        let promise = eventLoop.newPromise(of: T.self)
        
        self.whenSuccess { expectation in
            do {
                let mapped = try callback(expectation)
                mapped.cascade(promise: promise)
            } catch {
                promise.fail(error: error)
            }
        }
            
        self.whenFailure { error in
            promise.fail(error: error)
        }
        
        return promise.futureResult
    }
}

public protocol FutureType {
    associatedtype Expectation
    func whenSuccess(_ callback: @escaping (Expectation) -> Void)
    func whenFailure(_ callback: @escaping (Error) -> Void)
}

extension Future : FutureType {
    public typealias Expectation = T
    
}
