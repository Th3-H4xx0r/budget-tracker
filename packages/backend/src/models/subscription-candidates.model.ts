import {
  SUBSCRIPTION_CANDIDATE_STATUS,
  SUBSCRIPTION_DETECTION_SOURCE,
  SUBSCRIPTION_FREQUENCIES,
  RecordId,
  TRANSACTION_TYPES,
} from '@bt/shared/types';
import { IdColumn } from '@common/types/id-column';
import { Table, Column, Model, ForeignKey, BelongsTo, DataType } from 'sequelize-typescript';

import Accounts from './accounts.model';
import Subscriptions from './subscriptions.model';
import Users from './users.model';

@Table({
  tableName: 'SubscriptionCandidates',
  timestamps: false,
  freezeTableName: true,
})
export default class SubscriptionCandidates extends Model {
  @Column(IdColumn())
  declare id: RecordId;

  @ForeignKey(() => Users)
  @Column({
    type: DataType.INTEGER,
    allowNull: false,
  })
  userId!: number;

  @Column({
    type: DataType.STRING(200),
    allowNull: false,
  })
  suggestedName!: string;

  @Column({
    type: DataType.ENUM(...Object.values(SUBSCRIPTION_FREQUENCIES)),
    allowNull: false,
  })
  detectedFrequency!: SUBSCRIPTION_FREQUENCIES;

  @Column({
    type: DataType.BIGINT,
    allowNull: false,
    comment: 'Average amount in cents',
  })
  averageAmount!: number;

  @Column({
    type: DataType.STRING(3),
    allowNull: false,
  })
  currencyCode!: string;

  @ForeignKey(() => Accounts)
  @Column({
    type: DataType.UUID,
    allowNull: true,
  })
  accountId!: RecordId | null;

  @Column({
    type: DataType.ARRAY(DataType.UUID),
    allowNull: false,
    defaultValue: [],
  })
  sampleTransactionIds!: RecordId[];

  @Column({
    type: DataType.INTEGER,
    allowNull: false,
  })
  occurrenceCount!: number;

  @Column({
    type: DataType.FLOAT,
    allowNull: false,
  })
  confidenceScore!: number;

  @Column({
    type: DataType.FLOAT,
    allowNull: false,
  })
  medianIntervalDays!: number;

  @Column({
    type: DataType.ENUM(...Object.values(SUBSCRIPTION_CANDIDATE_STATUS)),
    allowNull: false,
    defaultValue: SUBSCRIPTION_CANDIDATE_STATUS.pending,
  })
  status!: SUBSCRIPTION_CANDIDATE_STATUS;

  @ForeignKey(() => Subscriptions)
  @Column({
    type: DataType.UUID,
    allowNull: true,
  })
  subscriptionId!: RecordId | null;

  @Column({
    type: DataType.DATE,
    allowNull: false,
    defaultValue: DataType.NOW,
  })
  detectedAt!: Date;

  @Column({
    type: DataType.DATE,
    allowNull: true,
  })
  lastOccurrenceAt!: Date | null;

  @Column({
    type: DataType.DATE,
    allowNull: true,
  })
  resolvedAt!: Date | null;

  /** Dedupe key: `payee:<payeeId>` or the `buildMerchantKey` key of the cluster. */
  @Column({
    type: DataType.STRING(200),
    allowNull: true,
  })
  merchantKey!: string | null;

  @Column({
    type: DataType.STRING(50),
    allowNull: false,
    defaultValue: TRANSACTION_TYPES.expense,
  })
  transactionType!: TRANSACTION_TYPES;

  /** MAD / median of the cluster amounts. */
  @Column({
    type: DataType.REAL,
    allowNull: true,
  })
  amountVariability!: number | null;

  @Column({
    type: DataType.STRING(20),
    allowNull: false,
    defaultValue: SUBSCRIPTION_DETECTION_SOURCE.heuristic,
  })
  detectionSource!: SUBSCRIPTION_DETECTION_SOURCE;

  @Column({
    type: DataType.TEXT,
    allowNull: true,
  })
  aiReason!: string | null;

  /** sha256(merchantKey + sorted tx ids) of the cluster last sent to AI review; unchanged clusters aren't re-sent. */
  @Column({
    type: DataType.STRING(64),
    allowNull: true,
  })
  aiFingerprint!: string | null;

  @Column({
    type: DataType.DATEONLY,
    allowNull: true,
  })
  nextExpectedDate!: string | null;

  @BelongsTo(() => Users)
  user!: Users;

  @BelongsTo(() => Accounts)
  account!: Accounts;

  @BelongsTo(() => Subscriptions)
  subscription!: Subscriptions;
}
