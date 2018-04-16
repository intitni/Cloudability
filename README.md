# Cloudability

[![CI Status](http://img.shields.io/travis/int123c/Cloudability.svg?style=flat)](https://travis-ci.org/int123c/Cloudability)
[![Version](https://img.shields.io/cocoapods/v/Cloudability.svg?style=flat)](http://cocoapods.org/pods/Cloudability)
[![License](https://img.shields.io/cocoapods/l/Cloudability.svg?style=flat)](http://cocoapods.org/pods/Cloudability)
[![Platform](https://img.shields.io/cocoapods/p/Cloudability.svg?style=flat)](http://cocoapods.org/pods/Cloudability)

## Example

To run the example project, clone the repo, and run `pod install` from the Example directory first.

## Installation

Cloudability is available through [CocoaPods](http://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod 'Cloudability'
```

## Usage

1. Mark your objects with `Cloudable`.
2. Create an instance of `Cloud` somewhere.
3. Call `cloud.switchOn(rule:completionHandler:)` to start it.
4. Done

When you delete an `Cloudable` object, please use `realm.delete(cloudableObject:)` instead.

Optionally,

- Exclude `PendingRelationship` and `SyncedEntity` from your realm configuration. Though they are stored in another realm file in documents/cloudability.realm.
- Listen to push notifications.
    By default, Cloudability creates database subscriptions for private and shared database. You can call `cloud.pull(_:)` when you recieve a notification.
- Conform your objects to `HasAfterMergeAction` and `HasBeforeDeletionAction`.

## Behaviours

It supports several `zoneType`s when you create a `Cloud`, but only `.sameZone(String)` is tested (I mean used in my app). It may lose some abilities if you are using the default `CKContainer` or the default `CKZone`.

When you `switchOn` a `Cloud`, it will perform sync immediately. If your device has not logged into iCloud, you will get an `Error` instead. You should check if it's an `CloudError` that you care.

By default, Cloudability creates database subscriptions for private and shared database. If you want other subscriptions, you have to do it yourself.

Cloudability will listen to database changes, and do pushing automatically. But realm observations don't care that much about deleted objects, so you should use  `realm.delete(cloudableObject:)` instead when deleting an `Cloudable` object.

Relations between objects are converted to `CKReference` when talking to CloudKit. `LinkingObjects` and relations to non-`Cloudable` objects will be ignored.

## It's still under construction

Not even unit tested. Used in my iOS app Best Before.

## Author

int123c, int123c@gmail.com

## License

Cloudability is available under the MIT license. See the LICENSE file for more info.
