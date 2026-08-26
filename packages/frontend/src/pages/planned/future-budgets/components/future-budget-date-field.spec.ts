import { mount } from '@vue/test-utils';

import FutureBudgetDateField from './future-budget-date-field.vue';

const DateFieldStub = {
  name: 'DateField',
  props: { modelValue: { type: Date, default: undefined } },
  emits: ['update:modelValue'],
  template: '<button type="button" @click="$emit(\'update:modelValue\', new Date(\'2026-09-15T12:00:00.000Z\'))" />',
};

describe('FutureBudgetDateField', () => {
  it('converts picker selections to the API date-only format', async () => {
    const wrapper = mount(FutureBudgetDateField, {
      props: { modelValue: '2026-08-26' },
      global: { stubs: { DateField: DateFieldStub } },
    });

    expect(wrapper.findComponent({ name: 'DateField' }).props('modelValue')).toEqual(new Date('2026-08-26T12:00:00'));
    await wrapper.find('button').trigger('click');

    expect(wrapper.emitted('update:modelValue')).toEqual([['2026-09-15']]);
  });
});
