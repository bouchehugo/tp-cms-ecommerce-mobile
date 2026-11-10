import type { Core } from '@strapi/strapi';

export default {
  /**
   * An asynchronous register function that runs before
   * your application is initialized.
   *
   * This gives you an opportunity to extend code.
   */
  register(/* { strapi }: { strapi: Core.Strapi } */) {},

  /**
   * An asynchronous bootstrap function that runs before
   * your application gets started.
   *
   * This gives you an opportunity to set up your data model,
   * run jobs, or perform some special logic.
   */
  async bootstrap({ strapi }: { strapi: Core.Strapi }) {
    if (process.env.SEED_DEMO_CATALOG !== 'true') return;
    const exemples = [
      { documentId: 'qa9koizmgo8en0xen3cppzi5', prix: 19.90, stock: 10 },
      { documentId: 'ccr15jnyugavfxn38p415tt1', prix: 29.90, stock: 5 },
    ];
    for (const exemple of exemples) {
      const articles = await strapi.db.query('api::article.article').findMany({
        where: { documentId: exemple.documentId },
      });
      for (const article of articles) {
        const data: Record<string, number> = {};
        if (article.prix == null) data.prix = exemple.prix;
        if (article.stock == null) data.stock = exemple.stock;
        if (Object.keys(data).length) {
          await strapi.db.query('api::article.article').update({ where: { id: article.id }, data });
        }
      }
    }
  },
};
