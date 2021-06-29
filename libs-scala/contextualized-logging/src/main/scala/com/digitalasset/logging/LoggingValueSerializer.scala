// Copyright (c) 2021 Digital Asset (Switzerland) GmbH and/or its affiliates. All rights reserved.
// SPDX-License-Identifier: Apache-2.0

package com.daml.logging

import com.fasterxml.jackson.core.JsonGenerator

private[logging] object LoggingValueSerializer {
  def writeValue(value: LoggingValue, generator: JsonGenerator): Unit = {
    value match {
      case LoggingValue.Empty =>
        generator.writeNull()
      case LoggingValue.OfString(value) =>
        generator.writeString(value)
      case LoggingValue.OfInt(value) =>
        generator.writeNumber(value)
      case LoggingValue.OfLong(value) =>
        generator.writeNumber(value)
      case LoggingValue.OfIterable(sequence) =>
        generator.writeStartArray()
        sequence.foreach(writeValue(_, generator))
        generator.writeEndArray()
    }
  }
}