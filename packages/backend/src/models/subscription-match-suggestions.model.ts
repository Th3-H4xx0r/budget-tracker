import {
  MatchReason,
  RecordId,
  SUBSCRIPTION_SUGGESTION_SOURCE,
  SUBSCRIPTION_SUGGESTION_STATUS,
} from '@bt/shared/types';
import { BelongsTo, Column, DataType, ForeignKey, Model, Table } from 'sequelize-typescript';

import Subscriptions from './subscriptions.model';
import Transactions from './transactions.model';
import Users from './users.model';

/**
 * A (subscription, transaction) pair proposed by the scoring matcher or by discovery. `dismissed`
 * rows are the user's rejection memory: the matcher never suggests or auto-links that pair again,
 * and an explicit link deletes the row.
 */
@Table({
  tableName: 'SubscriptionMatchSuggestions',
  timestamps: true,
  freezeTableName: true,
})
export default class SubscriptionMatchSuggestions extends Model {
  @ForeignKey(() => Subscriptions)
  @Column({ type: DataType.UUID, allowNull: false, primaryKey: true })
  subscriptionId!: RecordId;

  @ForeignKey(() => Transactions)
  @Column({ type: DataType.UUID, allowNull: false, primaryKey: true })
  transactionId!: RecordId;

  @ForeignKey(() => Users)
  @Column({ type: DataType.INTEGER, allowNull: false })
  userId!: number;

  @Column({ type: DataType.REAL, allowNull: false })
  score!: number;

  @Column({ type: DataType.JSONB, allowNull: false, defaultValue: [] })
  reasons!: MatchReason[];

  @Column({ type: DataType.STRING(20), allowNull: false, defaultValue: SUBSCRIPTION_SUGGESTION_STATUS.pending })
  status!: SUBSCRIPTION_SUGGESTION_STATUS;

  @Column({ type: DataType.STRING(20), allowNull: false, defaultValue: SUBSCRIPTION_SUGGESTION_SOURCE.engine })
  source!: SUBSCRIPTION_SUGGESTION_SOURCE;

  declare createdAt: Date;
  declare updatedAt: Date;

  @BelongsTo(() => Subscriptions)
  subscription!: Subscriptions;

  @BelongsTo(() => Transactions)
  transaction!: Transactions;
}
