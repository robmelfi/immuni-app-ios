// AnalyticsLogicTests.swift
// Copyright (C) 2020 Presidenza del Consiglio dei Ministri.
// Please refer to the AUTHORS file for more information.
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as
// published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

import Alamofire
@testable import Immuni
import ImmuniExposureNotification
import Models
import Networking
import XCTest

// swiftlint:disable superfluous_disable_command force_try implicitly_unwrapped_optional force_unwrapping force_cast

class AnalyticsLogicTests: XCTestCase {
  override func tearDown() {
    super.tearDown()
    DeterministicGenerator.randomValue = 0.5
  }
}

// MARK: Operational Info With Exposure

extension AnalyticsLogicTests {
  func testTriggersAnalyticsWithExposure() throws {
    let state = AppState()
    let getState = { state }
    let dispatchInterceptor = DispatchInterceptor()
    let dependencies = AppDependencies.mocked(getAppState: getState, dispatch: dispatchInterceptor.dispatchFunction)
    let context = AppSideEffectContext(dependencies: dependencies)

    let outcome = ExposureDetectionOutcome.fullDetection(Date(), ExposureDetectionSummary.noMatch, [], 0, 0)

    try Logic.Analytics.SendOperationalInfoIfNeeded(outcome: outcome).sideEffect(context)

    try XCTAssertContainsType(
      dispatchInterceptor.dispatchedItems,
      Logic.Analytics.StochasticallySendOperationalInfoWithExposure.self
    )
  }

  func testAnalyticsWithExposure() throws {
    let previousDate = Date(utcDay: 10, month: 9, year: 2020)
    let date = Date(utcDay: 10, month: 10, year: 2020)

    var state = AppState()
    state.configuration = Configuration(operationalInfoWithExposureSamplingRate: 0.7)
    state.analytics.eventWithExposureLastSent = previousDate.utcCalendarDay
    state.user.province = .alessandria

    let getState = { state }
    let dispatchInterceptor = DispatchInterceptor()

    let now = { date }
    let requestExecutor = MockRequestExecutor(mockedResult: .failure(NetworkManager.Error.badRequest))

    let token = "test_with_exposure"
    let tokenGenerator = MockDeviceTokenGenerator(result: .success(token))

    let dependencies = AppDependencies.mocked(
      getAppState: getState,
      dispatch: dispatchInterceptor.dispatchFunction,
      requestExecutor: requestExecutor,
      now: now,
      uniformDistributionGenerator: DeterministicGenerator.self,
      tokenGenerator: tokenGenerator
    )

    let context = AppSideEffectContext(dependencies: dependencies)

    try Logic.Analytics.StochasticallySendOperationalInfoWithExposure().sideEffect(context)

    XCTAssertEqual(dispatchInterceptor.dispatchedItems.count, 2)

    try XCTAssertContainsType(
      dispatchInterceptor.dispatchedItems,
      Logic.Analytics.UpdateEventWithExposureLastSent.self
    ) { value in
      XCTAssertEqual(value.day, date.utcCalendarDay)
    }

    try XCTAssertContainsType(
      dispatchInterceptor.dispatchedItems,
      Logic.Analytics.SendRequest.self
    ) { value in
      XCTAssertEqual(value.kind, .withExposure)
    }
  }

  func testAnalyticsWithExposureNoMonth() throws {
    let previousDate = Date(utcDay: 10, month: 10, year: 2020)
    let date = Date(utcDay: 1, month: 10, year: 2020)

    var state = AppState()
    state.configuration = Configuration(operationalInfoWithExposureSamplingRate: 0.7)
    state.analytics.eventWithExposureLastSent = previousDate.utcCalendarDay
    state.user.province = .alessandria

    let getState = { state }
    let dispatchInterceptor = DispatchInterceptor()

    let now = { date }

    let dependencies = AppDependencies.mocked(
      getAppState: getState,
      dispatch: dispatchInterceptor.dispatchFunction,
      now: now,
      uniformDistributionGenerator: DeterministicGenerator.self
    )

    let context = AppSideEffectContext(dependencies: dependencies)

    try Logic.Analytics.SendOperationalInfoIfNeeded(outcome: .fullDetection(now(), .noMatch, [], 0, 0)).sideEffect(context)

    try XCTAssertNotContainsType(
      dispatchInterceptor.dispatchedItems,
      Logic.Analytics.StochasticallySendOperationalInfoWithExposure.self
    )
    try XCTAssertNotContainsType(
      dispatchInterceptor.dispatchedItems,
      Logic.Analytics.StochasticallySendOperationalInfoWithoutExposure.self
    )
  }

  func testAnalyticsWithExposureNoRandom() throws {
    let previousDate = Date(utcDay: 10, month: 9, year: 2020)
    let date = Date(utcDay: 10, month: 10, year: 2020)

    var state = AppState()
    state.configuration = Configuration(operationalInfoWithExposureSamplingRate: 0.1)
    state.analytics.eventWithExposureLastSent = previousDate.utcCalendarDay
    state.user.province = .alessandria

    let getState = { state }
    let dispatchInterceptor = DispatchInterceptor()

    let now = { date }
    let requestExecutor = MockRequestExecutor(mockedResult: .failure(NetworkManager.Error.badRequest))

    let dependencies = AppDependencies.mocked(
      getAppState: getState,
      dispatch: dispatchInterceptor.dispatchFunction,
      requestExecutor: requestExecutor,
      now: now,
      uniformDistributionGenerator: DeterministicGenerator.self
    )

    let context = AppSideEffectContext(dependencies: dependencies)

    try Logic.Analytics.StochasticallySendOperationalInfoWithExposure().sideEffect(context)

    XCTAssertEqual(requestExecutor.executeMethodCalls.count, 0)

    XCTAssertEqual(dispatchInterceptor.dispatchedItems.count, 1)

    try XCTAssertType(
      dispatchInterceptor.dispatchedItems.first,
      Logic.Analytics.UpdateEventWithExposureLastSent.self
    ) { value in

      XCTAssertEqual(value.day, date.utcCalendarDay)
    }
  }

  func testUpdateAnalyticEventWithExposureLastSent() {
    var state = AppState()
    let calendarDay = Date(utcDay: 1, month: 10, year: 2020).utcCalendarDay

    Logic.Analytics.UpdateEventWithExposureLastSent(day: calendarDay).updateState(&state)
    XCTAssertEqual(state.analytics.eventWithExposureLastSent, calendarDay)
  }
}

// MARK: Operational Info Without Exposure

extension AnalyticsLogicTests {
  func testTriggersAnalyticsWithoutExposure() throws {
    var state = AppState()
    let now = Date()
    state.analytics.eventWithoutExposureWindow = .init(windowStart: now.addingTimeInterval(-1), windowDuration: 2)

    let getState = { state }

    let dispatchInterceptor = DispatchInterceptor()

    let dependencies = AppDependencies.mocked(getAppState: getState, dispatch: dispatchInterceptor.dispatchFunction, now: { now })
    let context = AppSideEffectContext(dependencies: dependencies)

    let outcome = ExposureDetectionOutcome.partialDetection(Date(), .noMatch, 0, 0)

    try Logic.Analytics.SendOperationalInfoIfNeeded(outcome: outcome).sideEffect(context)

    try XCTAssertContainsType(
      dispatchInterceptor.dispatchedItems,
      Logic.Analytics.StochasticallySendOperationalInfoWithoutExposure.self
    )
  }

  func testDoesNotTriggerWithError() throws {
    let state = AppState()
    let getState = { state }
    let dispatchInterceptor = DispatchInterceptor()
    let dependencies = AppDependencies.mocked(getAppState: getState, dispatch: dispatchInterceptor.dispatchFunction)
    let context = AppSideEffectContext(dependencies: dependencies)

    let outcome = ExposureDetectionOutcome.error(.notAuthorized)

    try Logic.Analytics.SendOperationalInfoIfNeeded(outcome: outcome).sideEffect(context)
    try XCTAssertNotContainsType(
      dispatchInterceptor.dispatchedItems,
      Logic.Analytics.StochasticallySendOperationalInfoWithExposure.self
    )
    try XCTAssertNotContainsType(
      dispatchInterceptor.dispatchedItems,
      Logic.Analytics.StochasticallySendOperationalInfoWithoutExposure.self
    )
  }

  func testDoesNotTriggerWithNotNecessary() throws {
    let state = AppState()
    let getState = { state }
    let dispatchInterceptor = DispatchInterceptor()
    let dependencies = AppDependencies.mocked(getAppState: getState, dispatch: dispatchInterceptor.dispatchFunction)
    let context = AppSideEffectContext(dependencies: dependencies)

    let outcome = ExposureDetectionOutcome.noDetectionNecessary

    try Logic.Analytics.SendOperationalInfoIfNeeded(outcome: outcome).sideEffect(context)
    try XCTAssertNotContainsType(
      dispatchInterceptor.dispatchedItems,
      Logic.Analytics.StochasticallySendOperationalInfoWithExposure.self
    )
    try XCTAssertNotContainsType(
      dispatchInterceptor.dispatchedItems,
      Logic.Analytics.StochasticallySendOperationalInfoWithoutExposure.self
    )
  }

  func testAnalyticsWithoutExposure() throws {
    let currentDayOfMonth = 10
    let previousDate = Date(utcDay: 10, month: 9, year: 2020)
    let date = Date(utcDay: currentDayOfMonth, month: 10, year: 2020)

    var state = AppState()
    state.configuration = Configuration(operationalInfoWithoutExposureSamplingRate: 0.7)
    state.analytics.eventWithExposureLastSent = previousDate.utcCalendarDay

    state.analytics.eventWithoutExposureWindow = .init(
      month: CalendarMonth(year: 2020, month: 10),
      shift: Double(currentDayOfMonth - 1) * AnalyticsState.OpportunityWindow.secondsInDay
    )

    state.user.province = .alessandria

    let getState = { state }
    let dispatchInterceptor = DispatchInterceptor()

    let now = { date }

    let dependencies = AppDependencies.mocked(
      getAppState: getState,
      dispatch: dispatchInterceptor.dispatchFunction,
      now: now,
      uniformDistributionGenerator: DeterministicGenerator.self
    )

    let context = AppSideEffectContext(dependencies: dependencies)

    try Logic.Analytics.StochasticallySendOperationalInfoWithoutExposure().sideEffect(context)

    XCTAssertEqual(dispatchInterceptor.dispatchedItems.count, 2)

    try XCTAssertContainsType(
      dispatchInterceptor.dispatchedItems,
      Logic.Analytics.UpdateEventWithoutExposureLastSent.self
    ) { value in
      XCTAssertEqual(value.day, date.utcCalendarDay)
    }

    try XCTAssertContainsType(
      dispatchInterceptor.dispatchedItems,
      Logic.Analytics.UpdateEventWithoutExposureLastSent.self
    ) { value in
      XCTAssertEqual(value.day, date.utcCalendarDay)
    }
  }

  func testAnalyticsWithoutExposureNoProvince() throws {
    let currentDayOfMonth = 10
    let previousDate = Date(utcDay: 10, month: 9, year: 2020)
    let date = Date(utcDay: currentDayOfMonth, month: 10, year: 2020)

    var state = AppState()
    state.configuration = Configuration(operationalInfoWithoutExposureSamplingRate: 0.7)
    state.analytics.eventWithExposureLastSent = previousDate.utcCalendarDay

    state.analytics.eventWithoutExposureWindow = .init(
      month: CalendarMonth(year: 2020, month: 10),
      shift: Double(currentDayOfMonth) * AnalyticsState.OpportunityWindow.secondsInDay
    )

    let getState = { state }
    let dispatchInterceptor = DispatchInterceptor()

    let now = { date }

    let dependencies = AppDependencies.mocked(
      getAppState: getState,
      dispatch: dispatchInterceptor.dispatchFunction,
      now: now,
      uniformDistributionGenerator: DeterministicGenerator.self
    )

    let context = AppSideEffectContext(dependencies: dependencies)

    let outcome = ExposureDetectionOutcome.partialDetection(date, .noMatch, 0, 0)
    try Logic.Analytics.SendOperationalInfoIfNeeded(outcome: outcome).sideEffect(context)

    try XCTAssertNotContainsType(
      dispatchInterceptor.dispatchedItems,
      Logic.Analytics.StochasticallySendOperationalInfoWithExposure.self
    )
    try XCTAssertNotContainsType(
      dispatchInterceptor.dispatchedItems,
      Logic.Analytics.StochasticallySendOperationalInfoWithoutExposure.self
    )
  }

  func testAnalyticsWithoutExposureNoMonthPassed() throws {
    let currentDayOfMonth = 10
    let previousDate = Date(utcDay: 10, month: 10, year: 2020)
    let date = Date(utcDay: currentDayOfMonth, month: 10, year: 2020)

    var state = AppState()
    state.configuration = Configuration(operationalInfoWithoutExposureSamplingRate: 0.7)
    state.analytics.eventWithExposureLastSent = previousDate.utcCalendarDay

    state.analytics.eventWithoutExposureWindow = .init(
      month: CalendarMonth(year: 2020, month: 10),
      shift: Double(currentDayOfMonth) * AnalyticsState.OpportunityWindow.secondsInDay
    )

    state.user.province = .alessandria

    let getState = { state }
    let dispatchInterceptor = DispatchInterceptor()

    let now = { date }

    let dependencies = AppDependencies.mocked(
      getAppState: getState,
      dispatch: dispatchInterceptor.dispatchFunction,
      now: now,
      uniformDistributionGenerator: DeterministicGenerator.self
    )

    let context = AppSideEffectContext(dependencies: dependencies)

    let outcome = ExposureDetectionOutcome.partialDetection(date, .noMatch, 0, 0)
    try Logic.Analytics.SendOperationalInfoIfNeeded(outcome: outcome).sideEffect(context)

    try XCTAssertNotContainsType(
      dispatchInterceptor.dispatchedItems,
      Logic.Analytics.StochasticallySendOperationalInfoWithExposure.self
    )
    try XCTAssertNotContainsType(
      dispatchInterceptor.dispatchedItems,
      Logic.Analytics.StochasticallySendOperationalInfoWithoutExposure.self
    )
  }

  func testAnalyticsWithoutExposureBeforeWindow() throws {
    let currentDayOfMonth = 10
    let previousDate = Date(utcDay: 10, month: 9, year: 2020)

    // "today" is the 10th of the month minus a second (that is, 23.59.59PM of 9th of the month)
    let date = Date(utcDay: currentDayOfMonth, month: 10, year: 2020).advanced(by: -1)

    var state = AppState()
    state.configuration = Configuration(operationalInfoWithoutExposureSamplingRate: 0.7)
    state.analytics.eventWithExposureLastSent = previousDate.utcCalendarDay

    state.analytics.eventWithoutExposureWindow = .init(
      month: CalendarMonth(year: 2020, month: 10),
      // just a second before the beginning of the time window
      shift: Double(currentDayOfMonth - 1) * AnalyticsState.OpportunityWindow.secondsInDay
    )

    state.user.province = .alessandria

    let getState = { state }
    let dispatchInterceptor = DispatchInterceptor()

    let now = { date }

    let dependencies = AppDependencies.mocked(
      getAppState: getState,
      dispatch: dispatchInterceptor.dispatchFunction,
      now: now,
      uniformDistributionGenerator: DeterministicGenerator.self
    )

    let context = AppSideEffectContext(dependencies: dependencies)

    let outcome = ExposureDetectionOutcome.partialDetection(date, .noMatch, 0, 0)
    try Logic.Analytics.SendOperationalInfoIfNeeded(outcome: outcome).sideEffect(context)

    try XCTAssertNotContainsType(
      dispatchInterceptor.dispatchedItems,
      Logic.Analytics.StochasticallySendOperationalInfoWithExposure.self
    )
    try XCTAssertNotContainsType(
      dispatchInterceptor.dispatchedItems,
      Logic.Analytics.StochasticallySendOperationalInfoWithoutExposure.self
    )
  }

  func testAnalyticsWithoutExposureAfterWindow() throws {
    let currentDayOfMonth = 10
    let previousDate = Date(utcDay: 10, month: 9, year: 2020)

    // "today" is the 11th of the month (that is, 00.00AM of 10th of the month)
    // exactly when the window closes
    let date = Date(utcDay: currentDayOfMonth + 1, month: 10, year: 2020)

    var state = AppState()
    state.configuration = Configuration(operationalInfoWithoutExposureSamplingRate: 0.7)
    state.analytics.eventWithExposureLastSent = previousDate.utcCalendarDay

    state.analytics.eventWithoutExposureWindow = .init(
      month: CalendarMonth(year: 2020, month: 10),
      // just a second before the beginning of the time window
      shift: Double(currentDayOfMonth - 1) * AnalyticsState.OpportunityWindow.secondsInDay
    )

    state.user.province = .alessandria

    let getState = { state }
    let dispatchInterceptor = DispatchInterceptor()

    let now = { date }

    let dependencies = AppDependencies.mocked(
      getAppState: getState,
      dispatch: dispatchInterceptor.dispatchFunction,
      now: now,
      uniformDistributionGenerator: DeterministicGenerator.self
    )

    let context = AppSideEffectContext(dependencies: dependencies)

    let outcome = ExposureDetectionOutcome.partialDetection(date, .noMatch, 0, 0)
    try Logic.Analytics.SendOperationalInfoIfNeeded(outcome: outcome).sideEffect(context)

    try XCTAssertNotContainsType(
      dispatchInterceptor.dispatchedItems,
      Logic.Analytics.StochasticallySendOperationalInfoWithExposure.self
    )
    try XCTAssertNotContainsType(
      dispatchInterceptor.dispatchedItems,
      Logic.Analytics.StochasticallySendOperationalInfoWithoutExposure.self
    )
  }

  func testAnalyticsWithoutExposureFailSampling() throws {
    let currentDayOfMonth = 10
    let previousDate = Date(utcDay: 10, month: 9, year: 2020)
    let date = Date(utcDay: currentDayOfMonth, month: 10, year: 2020)

    var state = AppState()
    state.configuration = Configuration(operationalInfoWithoutExposureSamplingRate: 0.1)
    state.analytics.eventWithExposureLastSent = previousDate.utcCalendarDay

    state.analytics.eventWithoutExposureWindow = .init(
      month: CalendarMonth(year: 2020, month: 10),
      shift: Double(currentDayOfMonth - 1) * AnalyticsState.OpportunityWindow.secondsInDay
    )

    state.user.province = .alessandria

    let getState = { state }
    let dispatchInterceptor = DispatchInterceptor()

    let now = { date }
    let requestExecutor = MockRequestExecutor(mockedResult: .failure(NetworkManager.Error.badRequest))

    let dependencies = AppDependencies.mocked(
      getAppState: getState,
      dispatch: dispatchInterceptor.dispatchFunction,
      requestExecutor: requestExecutor,
      now: now,
      uniformDistributionGenerator: DeterministicGenerator.self
    )

    let context = AppSideEffectContext(dependencies: dependencies)

    try Logic.Analytics.StochasticallySendOperationalInfoWithoutExposure().sideEffect(context)

    XCTAssertEqual(requestExecutor.executeMethodCalls.count, 0)

    XCTAssertEqual(dispatchInterceptor.dispatchedItems.count, 1)

    try XCTAssertType(
      dispatchInterceptor.dispatchedItems.first,
      Logic.Analytics.UpdateEventWithoutExposureLastSent.self
    ) { value in

      XCTAssertEqual(value.day, date.utcCalendarDay)
    }
  }

  func testUpdateOpportunityWindow() throws {
    let currentDayOfMonth = 10
    let previousDate = Date(utcDay: 10, month: 9, year: 2020)

    let date = Date(utcDay: currentDayOfMonth, month: 10, year: 2020)

    var state = AppState()
    state.configuration = Configuration(operationalInfoWithoutExposureSamplingRate: 0.7)
    state.analytics.eventWithExposureLastSent = previousDate.utcCalendarDay
    state.analytics.eventWithoutExposureWindow = .init(month: previousDate.utcCalendarMonth, shift: 100)
    state.user.province = .alessandria

    let getState = { state }
    let dispatchInterceptor = DispatchInterceptor()
    let now = { date }
    DeterministicGenerator.randomValue = 500

    let dependencies = AppDependencies.mocked(
      getAppState: getState,
      dispatch: dispatchInterceptor.dispatchFunction,
      now: now,
      uniformDistributionGenerator: DeterministicGenerator.self
    )

    let context = AppSideEffectContext(dependencies: dependencies)

    try Logic.Analytics.UpdateEventWithoutExposureOpportunityWindowIfNeeded().sideEffect(context)

    XCTAssertEqual(dispatchInterceptor.dispatchedItems.count, 1)

    try XCTAssertType(
      dispatchInterceptor.dispatchedItems.first,
      Logic.Analytics.SetEventWithoutExposureOpportunityWindow.self
    ) { value in

      XCTAssertEqual(
        value.window,
        AnalyticsState
          .OpportunityWindow(
            month: date.utcCalendarMonth,
            shift: 500,
            windowDuration: AnalyticsState.OpportunityWindow.secondsInDay
          )
      )
    }
  }

  func testUpdateOpportunityWindowAlreadyUpdated() throws {
    let currentDayOfMonth = 10
    let previousDate = Date(utcDay: 10, month: 10, year: 2020)

    let date = Date(utcDay: currentDayOfMonth, month: 10, year: 2020)

    var state = AppState()
    state.configuration = Configuration(operationalInfoWithoutExposureSamplingRate: 0.7)
    state.analytics.eventWithExposureLastSent = previousDate.utcCalendarDay
    state.analytics.eventWithoutExposureWindow = .init(month: previousDate.utcCalendarMonth, shift: 100)
    state.user.province = .alessandria

    let getState = { state }
    let dispatchInterceptor = DispatchInterceptor()
    let now = { date }

    let dependencies = AppDependencies.mocked(
      getAppState: getState,
      dispatch: dispatchInterceptor.dispatchFunction,
      now: now,
      uniformDistributionGenerator: DeterministicGenerator.self
    )

    let context = AppSideEffectContext(dependencies: dependencies)

    try Logic.Analytics.UpdateEventWithoutExposureOpportunityWindowIfNeeded().sideEffect(context)

    XCTAssertEqual(dispatchInterceptor.dispatchedItems.count, 0)
  }

  func testUpdateEventWithoutExposureLastSent() {
    var state = AppState()
    let calendarDay = Date(utcDay: 1, month: 10, year: 2020).utcCalendarDay

    Logic.Analytics.UpdateEventWithoutExposureLastSent(day: calendarDay).updateState(&state)
    XCTAssertEqual(state.analytics.eventWithoutExposureLastSent, calendarDay)
  }

  func testSetEventWithoutExposureOpportunityWindow() {
    var state = AppState()
    let window = AnalyticsState.OpportunityWindow(month: CalendarMonth(year: 2020, month: 10), shift: 10)

    Logic.Analytics.SetEventWithoutExposureOpportunityWindow(window: window).updateState(&state)
    XCTAssertEqual(state.analytics.eventWithoutExposureWindow, window)
  }
}

// MARK: Dummy

extension AnalyticsLogicTests {
  func testSendDummyRequestIfWithinOpportunityWindow() throws {
    let now = Date()
    var state = AppState()
    state.analytics.dummyTrafficOpportunityWindow = .init(windowStart: now.addingTimeInterval(-1), windowDuration: 2)

    let getState = { state }
    let dispatchInterceptor = DispatchInterceptor()

    let dependencies = AppDependencies.mocked(
      getAppState: getState,
      dispatch: dispatchInterceptor.dispatchFunction,
      uniformDistributionGenerator: DeterministicGenerator.self
    )

    let context = AppSideEffectContext(dependencies: dependencies)

    try Logic.Analytics.SendOperationalInfoIfNeeded(outcome: .noDetectionNecessary).sideEffect(context)
    XCTAssertEqual(dispatchInterceptor.dispatchedItems.count, 1)
    try XCTAssertType(
      dispatchInterceptor.dispatchedItems.first,
      Logic.Analytics.SendDummyAnalyticsAndUpdateOpportunityWindow.self
    )
  }

  func testDoesNotSendDummyRequestIfBeforeOpportunityWindow() throws {
    let now = Date()
    var state = AppState()
    state.analytics.dummyTrafficOpportunityWindow = .init(windowStart: now.addingTimeInterval(1), windowDuration: 2)

    let getState = { state }
    let dispatchInterceptor = DispatchInterceptor()

    let dependencies = AppDependencies.mocked(
      getAppState: getState,
      dispatch: dispatchInterceptor.dispatchFunction,
      uniformDistributionGenerator: DeterministicGenerator.self
    )

    let context = AppSideEffectContext(dependencies: dependencies)

    try Logic.Analytics.SendOperationalInfoIfNeeded(outcome: .noDetectionNecessary).sideEffect(context)
    try XCTAssertNotContainsType(
      dispatchInterceptor.dispatchedItems,
      Logic.Analytics.SendDummyAnalyticsAndUpdateOpportunityWindow.self
    )
  }

  func testDoesNotSendDummyRequestIfAfterOpportunityWindow() throws {
    let now = Date()
    var state = AppState()
    state.analytics.dummyTrafficOpportunityWindow = .init(windowStart: now.addingTimeInterval(-2), windowDuration: 1)

    let getState = { state }
    let dispatchInterceptor = DispatchInterceptor()

    let dependencies = AppDependencies.mocked(
      getAppState: getState,
      dispatch: dispatchInterceptor.dispatchFunction,
      uniformDistributionGenerator: DeterministicGenerator.self
    )

    let context = AppSideEffectContext(dependencies: dependencies)

    try Logic.Analytics.SendOperationalInfoIfNeeded(outcome: .noDetectionNecessary).sideEffect(context)
    try XCTAssertNotContainsType(
      dispatchInterceptor.dispatchedItems,
      Logic.Analytics.SendDummyAnalyticsAndUpdateOpportunityWindow.self
    )
  }

  func testAlwaysUpdatesDummyOpportunityWindowIfExpired() throws {
    var state = AppState()
    state.analytics.dummyTrafficOpportunityWindow = .distantPast

    let getState = { state }

    let possibleOutcomes: [ExposureDetectionOutcome] = [
      .error(.notAuthorized),
      .fullDetection(Date(), .noMatch, [], 0, 0),
      .partialDetection(Date(), .noMatch, 0, 0),
      .noDetectionNecessary
    ]

    for outcome in possibleOutcomes {
      let dispatchInterceptor = DispatchInterceptor()

      let dependencies = AppDependencies.mocked(
        getAppState: getState,
        dispatch: dispatchInterceptor.dispatchFunction,
        uniformDistributionGenerator: DeterministicGenerator.self
      )

      let context = AppSideEffectContext(dependencies: dependencies)

      try Logic.Analytics.SendOperationalInfoIfNeeded(outcome: outcome).sideEffect(context)
      try XCTAssertContainsType(dispatchInterceptor.dispatchedItems, Logic.Analytics.UpdateDummyTrafficOpportunityWindow.self)
    }
  }

  func testSetsTheCorrectDummyTrafficOpportunityWindow() throws {
    var state = AppState()
    state.analytics.dummyTrafficOpportunityWindow = .distantPast

    let date = Date()

    let getState = { state }
    let dispatchInterceptor = DispatchInterceptor()

    let dependencies = AppDependencies.mocked(
      getAppState: getState,
      dispatch: dispatchInterceptor.dispatchFunction,
      now: { date },
      exponentialDistributionGenerator: DeterministicGenerator.self
    )

    let context = AppSideEffectContext(dependencies: dependencies)

    try Logic.Analytics.UpdateDummyTrafficOpportunityWindow().sideEffect(context)
    try XCTAssertType(
      dispatchInterceptor.dispatchedItems.first,
      Logic.Analytics.SetDummyTrafficOpportunityWindow.self
    ) { dispatchable in
      XCTAssertEqual(dispatchable.now, date)
      XCTAssertEqual(dispatchable.dummyTrafficStochasticDelay, 0.5)
    }
  }

  func testSetDummyTrafficOpportunityWindow() {
    var state = AppState()
    let now = Date()
    let stochasticDelay = 42.0

    Logic.Analytics.SetDummyTrafficOpportunityWindow(dummyTrafficStochasticDelay: stochasticDelay, now: now).updateState(&state)
    XCTAssertEqual(state.analytics.dummyTrafficOpportunityWindow.windowStart, now.addingTimeInterval(stochasticDelay))
    XCTAssertEqual(state.analytics.dummyTrafficOpportunityWindow.windowDuration, 24 * 60 * 60)
  }
}

// MARK: Send Request

extension AnalyticsLogicTests {
  func testSendAnalyticsRequestWithExposure() throws {
    let previousDate = Date(utcDay: 10, month: 9, year: 2020)
    let date = Date(utcDay: 10, month: 10, year: 2020)

    var state = AppState()
    state.configuration = Configuration(operationalInfoWithExposureSamplingRate: 0.7)
    state.analytics.eventWithExposureLastSent = previousDate.utcCalendarDay
    state.user.province = .alessandria

    let getState = { state }
    let dispatchInterceptor = DispatchInterceptor()

    let now = { date }
    let requestExecutor = MockRequestExecutor(mockedResult: .failure(NetworkManager.Error.badRequest))

    let token = "test_with_exposure"
    let tokenGenerator = MockDeviceTokenGenerator(result: .success(token))

    let dependencies = AppDependencies.mocked(
      getAppState: getState,
      dispatch: dispatchInterceptor.dispatchFunction,
      requestExecutor: requestExecutor,
      now: now,
      uniformDistributionGenerator: DeterministicGenerator.self,
      tokenGenerator: tokenGenerator
    )

    let context = AppSideEffectContext(dependencies: dependencies)

    try Logic.Analytics.SendRequest(kind: .withExposure).sideEffect(context)

    let expectedRequest = AnalyticsRequest(
      body:
      .init(
        province: state.user.province!,
        exposureNotificationStatus: state.environment.exposureNotificationAuthorizationStatus,
        pushNotificationStatus: state.environment.pushNotificationAuthorizationStatus,
        riskyExposureDetected: true,
        deviceToken: token.data(using: .utf8)!
      ),
      isDummy: false
    )

    XCTAssertEqual(requestExecutor.executeMethodCalls.count, 1)

    try XCTAssertType(requestExecutor.executeMethodCalls.first, AnalyticsRequest.self) { value in

      XCTAssertEqual(value, expectedRequest)
    }
  }

  func testSendAnalyticsRequestWithoutExposure() throws {
    let currentDayOfMonth = 10
    let previousDate = Date(utcDay: 10, month: 9, year: 2020)
    let date = Date(utcDay: currentDayOfMonth, month: 10, year: 2020)

    var state = AppState()
    state.configuration = Configuration(operationalInfoWithoutExposureSamplingRate: 0.7)
    state.analytics.eventWithExposureLastSent = previousDate.utcCalendarDay

    state.analytics.eventWithoutExposureWindow = .init(
      month: CalendarMonth(year: 2020, month: 10),
      shift: Double(currentDayOfMonth - 1) * AnalyticsState.OpportunityWindow.secondsInDay
    )

    state.user.province = .alessandria

    let getState = { state }
    let dispatchInterceptor = DispatchInterceptor()

    let now = { date }
    let requestExecutor = MockRequestExecutor(mockedResult: .failure(NetworkManager.Error.badRequest))

    let token = "test_with_exposure"
    let tokenGenerator = MockDeviceTokenGenerator(result: .success(token))

    let dependencies = AppDependencies.mocked(
      getAppState: getState,
      dispatch: dispatchInterceptor.dispatchFunction,
      requestExecutor: requestExecutor,
      now: now,
      uniformDistributionGenerator: DeterministicGenerator.self,
      tokenGenerator: tokenGenerator
    )

    let context = AppSideEffectContext(dependencies: dependencies)

    try Logic.Analytics.SendRequest(kind: .withoutExposure).sideEffect(context)

    let expectedRequest = AnalyticsRequest(
      body: .init(
        province: state.user.province!,
        exposureNotificationStatus: state.environment.exposureNotificationAuthorizationStatus,
        pushNotificationStatus: state.environment.pushNotificationAuthorizationStatus,
        riskyExposureDetected: false,
        deviceToken: token.data(using: .utf8)!
      ),
      isDummy: false
    )

    XCTAssertEqual(requestExecutor.executeMethodCalls.count, 1)

    try XCTAssertType(requestExecutor.executeMethodCalls.first, AnalyticsRequest.self) { value in
      XCTAssertEqual(value, expectedRequest)
    }
  }

  func testSendDummyAnalyticsRequest() throws {
    var state = AppState()
    state.user.province = .alessandria

    let getState = { state }
    let dispatchInterceptor = DispatchInterceptor()

    let requestExecutor = MockRequestExecutor(mockedResult: .failure(NetworkManager.Error.badRequest))

    let token = "test_with_exposure"
    let tokenGenerator = MockDeviceTokenGenerator(result: .success(token))

    let dependencies = AppDependencies.mocked(
      getAppState: getState,
      dispatch: dispatchInterceptor.dispatchFunction,
      requestExecutor: requestExecutor,
      uniformDistributionGenerator: DeterministicGenerator.self,
      tokenGenerator: tokenGenerator
    )

    let context = AppSideEffectContext(dependencies: dependencies)

    try Logic.Analytics.SendRequest(kind: .dummy).sideEffect(context)

    XCTAssertEqual(requestExecutor.executeMethodCalls.count, 1)

    try XCTAssertType(requestExecutor.executeMethodCalls.first, AnalyticsRequest.self) { request in
      XCTAssertEqual(request.isDummy, true)
      XCTAssertEqual(request.jsonParameter.deviceToken, token.data(using: .utf8)!.base64EncodedString())
    }
  }
}

// MARK: Helpers

private enum DeterministicGenerator: UniformDistributionGenerator, ExponentialDistributionGenerator {
  static var randomValue = 0.5

  static func random(in range: Range<Double>) -> Double {
    return self.randomValue
  }

  static func exponentialRandom(with mean: Double) -> Double {
    return self.randomValue
  }
}

private extension Date {
  init(utcDay: Int, month: Int, year: Int) {
    var dateComponents = DateComponents()
    dateComponents.year = year
    dateComponents.month = month
    dateComponents.day = utcDay

    var calendar = Calendar.current
    calendar.timeZone = TimeZone(abbreviation: "UTC")!
    self = calendar.date(from: dateComponents)!
  }
}
