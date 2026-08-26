import { BUDGET_STATUSES, BUDGET_TYPES, RecordId } from '@bt/shared/types';
import { IdColumn } from '@common/types/id-column';
import { Money } from '@common/types/money';
import { MoneyField } from '@common/types/money-column';
import Categories from '@models/categories.model';
import Users from '@models/users.model';
import { BelongsTo, BelongsToMany, Column, DataType, ForeignKey, Model, Table } from 'sequelize-typescript';

import FutureBudgetPlanCategories from './future-budget-plan-categories.model';

@Table({ tableName: 'FutureBudgetPlans', timestamps: true, freezeTableName: true })
export default class FutureBudgetPlans extends Model {
  @Column(IdColumn()) declare id: RecordId;
  @ForeignKey(() => Users) @Column({ type: DataType.INTEGER, allowNull: false }) userId!: number;
  @Column({ type: DataType.STRING(200), allowNull: false }) name!: string;
  @Column({ type: DataType.ENUM(...Object.values(BUDGET_TYPES)), allowNull: false }) type!: BUDGET_TYPES;
  @Column({ type: DataType.ENUM(...Object.values(BUDGET_STATUSES)), allowNull: false }) status!: BUDGET_STATUSES;
  @Column({ type: DataType.DATEONLY, allowNull: false }) startDate!: string;
  @Column({ type: DataType.DATEONLY, allowNull: false }) endDate!: string;
  @MoneyField({ storage: 'cents', allowNull: false }) declare salaryAmount: Money;
  @Column({ type: DataType.STRING(20), allowNull: false }) salaryFrequency!: string;
  @Column({ type: DataType.INTEGER, allowNull: true }) salaryIntervalDays!: number | null;
  @Column({ type: DataType.DATEONLY, allowNull: true }) salaryAnchorDate!: string | null;
  @Column({ type: DataType.UUID, allowNull: true }) salaryCategoryId!: RecordId | null;
  @Column({ type: DataType.INTEGER, allowNull: false }) salaryProfileRevision!: number;
  @Column({ type: DataType.INTEGER, allowNull: true }) dismissedSalaryProfileRevision!: number | null;
  @BelongsTo(() => Users) user!: Users;
  @BelongsToMany(() => Categories, () => FutureBudgetPlanCategories) categories!: Categories[];
}
