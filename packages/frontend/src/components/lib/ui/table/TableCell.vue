<script setup lang="ts">
import { cn } from '@/lib/utils';
import { useAttrs } from 'vue';

const attrs = useAttrs();
</script>

<template>
  <td :class="cn('p-3 align-middle [&:has([role=checkbox])]:pr-0', attrs.class as string)">
    <slot />
  </td>
</template>
