import { RecordId, TRANSACTION_TYPES } from '@bt/shared/types';
import { IdColumn } from '@common/types/id-column';
import { Money } from '@common/types/money';
import { MoneyField } from '@common/types/money-column';
import Categories from '@models/categories.model';
import Subscriptions from '@models/subscriptions.model';
import Transactions from '@models/transactions.model';
import { BelongsTo, Column, DataType, ForeignKey, Model, Table } from 'sequelize-typescript';

import FutureBudgetPlans from './future-budget-plans.model';

@Table({ tableName: 'FutureBudgetEntries', timestamps: true, freezeTableName: true })
export default class FutureBudgetEntries extends Model {
  @Column(IdColumn()) declare id: RecordId;
  @ForeignKey(() => FutureBudgetPlans) @Column({ type: DataType.UUID, allowNull: false }) planId!: RecordId;
  @Column({ type: DataType.STRING(20), allowNull: false }) transactionType!: TRANSACTION_TYPES;
  @MoneyField({ storage: 'cents', allowNull: false }) declare amount: Money;
  @Column({ type: DataType.DATEONLY, allowNull: false }) date!: string;
  @ForeignKey(() => Categories) @Column({ type: DataType.UUID, allowNull: true }) categoryId!: RecordId | null;
  @Column({ type: DataType.TEXT, allowNull: true }) note!: string | null;
  @Column({ type: DataType.STRING(20), allowNull: true }) frequency!: string | null;
  @Column({ type: DataType.INTEGER, allowNull: true }) intervalDays!: number | null;
  /** The real transaction an auto-added entry mirrors; null for user-entered entries. Unique per plan. */
  @ForeignKey(() => Transactions) @Column({ type: DataType.UUID, allowNull: true }) transactionId!: RecordId | null;
  /** The recurring payment `transactionId` is actively linked to, so the plan counts that occurrence once. */
  @ForeignKey(() => Subscriptions) @Column({ type: DataType.UUID, allowNull: true }) subscriptionId!: RecordId | null;
  @BelongsTo(() => FutureBudgetPlans) plan!: FutureBudgetPlans;
  @BelongsTo(() => Categories) category!: Categories;
}
