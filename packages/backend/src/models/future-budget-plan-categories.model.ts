import { RecordId } from '@bt/shared/types';
import Categories from '@models/categories.model';
import { Column, DataType, ForeignKey, Model, Table } from 'sequelize-typescript';

import FutureBudgetPlans from './future-budget-plans.model';

@Table({ tableName: 'FutureBudgetPlanCategories', timestamps: false, freezeTableName: true })
export default class FutureBudgetPlanCategories extends Model {
  @ForeignKey(() => FutureBudgetPlans) @Column({ primaryKey: true, type: DataType.UUID }) planId!: RecordId;
  @ForeignKey(() => Categories) @Column({ primaryKey: true, type: DataType.UUID }) categoryId!: RecordId;
}
