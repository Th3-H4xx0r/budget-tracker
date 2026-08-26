import { RecordId } from '@bt/shared/types';
import { IdColumn } from '@common/types/id-column';
import { Money } from '@common/types/money';
import { MoneyField } from '@common/types/money-column';
import Categories from '@models/categories.model';
import Subscriptions from '@models/subscriptions.model';
import { BelongsTo, Column, DataType, ForeignKey, Model, Table } from 'sequelize-typescript';

import FutureBudgetPlans from './future-budget-plans.model';

@Table({ tableName: 'FutureBudgetRecurringOverrides', timestamps: true, freezeTableName: true })
export default class FutureBudgetRecurringOverrides extends Model {
  @Column(IdColumn()) declare id: RecordId;
  @ForeignKey(() => FutureBudgetPlans) @Column({ type: DataType.UUID, allowNull: false }) planId!: RecordId;
  @ForeignKey(() => Subscriptions) @Column({ type: DataType.UUID, allowNull: false }) subscriptionId!: RecordId;
  @Column({ type: DataType.BOOLEAN, allowNull: false, defaultValue: true }) isIncluded!: boolean;
  @MoneyField({ storage: 'cents', allowNull: true }) declare amount: Money | null;
  @ForeignKey(() => Categories) @Column({ type: DataType.UUID, allowNull: true }) categoryId!: RecordId | null;
  @Column({ type: DataType.DATEONLY, allowNull: true }) nextOccurrenceDate!: string | null;
  @BelongsTo(() => FutureBudgetPlans) plan!: FutureBudgetPlans;
  @BelongsTo(() => Subscriptions) subscription!: Subscriptions;
  @BelongsTo(() => Categories) category!: Categories;
}
