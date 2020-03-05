// Copyright (c) 2020 The DAML Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0

package com.digitalasset.platform.index

import com.digitalasset.daml.lf.data.Ref
import com.digitalasset.ledger.api.v1.event.{ArchivedEvent, CreatedEvent, Event}
import com.digitalasset.platform.index.TransactionConversion.removeTransient
import org.scalatest.{Matchers, WordSpec}

final class TransactionConversionSpec extends WordSpec with Matchers {

  private val contractId1 = Ref.ContractIdString.assertFromString("contractId")
  private val contractId2 = Ref.ContractIdString.assertFromString("contractId2")
  private def create(contractId: Ref.ContractIdString): Event =
    Event(
      Event.Event.Created(
        CreatedEvent("", contractId, None, None, None, Seq.empty, Seq.empty, Seq.empty, None)))

  private val create1 = create(contractId1)
  private val create2 = create(contractId2)
  private val archive1 = Event(
    Event.Event.Archived(ArchivedEvent("", contractId1, None, Seq.empty)))

  "removeTransient" should {

    "remove Created and Archived events for the same contract from the transaction" in {
      removeTransient(Vector(create1, archive1)) shouldEqual Nil
    }

    "do not touch events with different contract identifiers" in {
      val events = Vector(create2, archive1)
      removeTransient(events) shouldBe events
    }

    "do not touch individual Created events" in {
      val events = Vector(create1)
      removeTransient(events) shouldEqual events
    }

    "do not touch individual Archived events" in {
      val events = Vector(archive1)
      removeTransient(events) shouldEqual events
    }
  }
}
