import { RecordId } from '@bt/shared/types';
import { Money } from '@common/types/money';
import { MoneyField } from '@common/types/money-column';
import Categories from '@models/categories.model';
import Users from '@models/users.model';
import { BelongsTo, Column, DataType, ForeignKey, Model, Table } from 'sequelize-typescript';

@Table({ tableName: 'FutureBudgetSettings', timestamps: true, freezeTableName: true })
export default class FutureBudgetSettings extends Model {
  @ForeignKey(() => Users) @Column({ type: DataType.INTEGER, primaryKey: true }) userId!: number;
  @MoneyField({ storage: 'cents', allowNull: false }) declare salaryAmount: Money;
  @Column({ type: DataType.STRING(20), allowNull: false }) salaryFrequency!: string;
  @Column({ type: DataType.INTEGER, allowNull: true }) salaryIntervalDays!: number | null;
  @Column({ type: DataType.DATEONLY, allowNull: true }) salaryAnchorDate!: string | null;
  @ForeignKey(() => Categories) @Column({ type: DataType.UUID, allowNull: true }) salaryCategoryId!: RecordId | null;
  @Column({ type: DataType.INTEGER, allowNull: false }) revision!: number;
  @BelongsTo(() => Users) user!: Users;
  @BelongsTo(() => Categories) salaryCategory!: Categories;
}
