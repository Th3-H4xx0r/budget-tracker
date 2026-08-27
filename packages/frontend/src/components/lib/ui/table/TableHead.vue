<script setup lang="ts">
import { cn } from '@/lib/utils';
import { useAttrs } from 'vue';

const attrs = useAttrs();
</script>

<template>
  <th
    :class="
      cn(
        'text-muted-foreground h-10 px-3 text-left align-middle font-medium whitespace-nowrap [&:has([role=checkbox])]:pr-0',
        attrs.class as string,
      )
    "
  >
    <slot />
  </th>
</template>
