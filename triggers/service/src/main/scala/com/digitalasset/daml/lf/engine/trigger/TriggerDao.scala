// Copyright (c) 2020 Digital Asset (Switzerland) GmbH and/or its affiliates. All rights reserved.
// SPDX-License-Identifier: Apache-2.0

package com.daml.lf.engine.trigger

import cats.effect.{ContextShift, IO}
import cats.syntax.apply._
import cats.syntax.functor._
import doobie._
import doobie.LogHandler
import doobie.free.connection.ConnectionIO
import doobie.implicits._
import doobie.util.log

import scala.concurrent.ExecutionContext

object Connection {

  type T = Transactor.Aux[IO, Unit]

  def connect(jdbcDriver: String, jdbcUrl: String, username: String, password: String)(
      implicit cs: ContextShift[IO]): T =
    Transactor
      .fromDriverManager[IO](jdbcDriver, jdbcUrl, username, password)(IO.ioConcurrentEffect(cs), cs)
}

class TriggerDao(xa: Connection.T) {

  implicit val logHandler: log.LogHandler = doobie.util.log.LogHandler.jdkLogHandler

  def transact[A](query: ConnectionIO[A]): IO[A] =
    query.transact(xa)
}

object TriggerDao {
  def apply(c: JdbcConfig)(implicit ec: ExecutionContext): TriggerDao = {
    val cs: ContextShift[IO] = IO.contextShift(ec)
    new TriggerDao(Connection.connect(JdbcConfig.driver, c.url, c.user, c.password)(cs))
  }

  def initialize(implicit log: LogHandler): ConnectionIO[Unit] = {
    val createTriggerTable: Fragment = sql"""
        create table running_triggers(
          trigger_id uuid primary key,
          party_token text not null,
          package_id text not null,
          module_name text not null,
          trigger_name text not null
        )
      """
    val createDalfTable: Fragment = sql"""
        create table dalfs(
          package_id text primary key,
          package bytea not null
        )
      """
    (createTriggerTable.update.run
      *> createDalfTable.update.run).void
  }
}
